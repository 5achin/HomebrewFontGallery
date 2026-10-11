import AppKit
import CryptoKit
import Foundation

enum UpdateError: Error, Equatable {
    /// GitHub couldn't be reached, or answered with an error.
    case network
    /// GitHub answered, but not with a release.
    case unreadableRelease
    case downloadFailed
    /// The zip isn't the one GitHub recorded for the release.
    case checksumMismatch
    case unpackFailed
    /// The zip didn't hold this app at the expected build, with an intact signature.
    case notTheExpectedApp
    /// macOS is running the app from a read-only copy, as it does for a quarantined app
    /// opened straight from the Downloads folder.
    case translocated
    /// The folder holding the app can't be changed.
    case folderNotWritable
    case replaceFailed
    case cancelled
}

/// Finds, downloads, checks and installs a newer build of the app from its GitHub releases.
/// The checksum and the signature show the download arrived whole and unchanged. The app is
/// ad-hoc signed, so neither can show who built it: that rests on GitHub's HTTPS.
struct UpdateService {
    /// The app to replace.
    var bundleURL = Bundle.main.bundleURL
    var bundleIdentifier = Bundle.main.bundleIdentifier

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    // MARK: Checking

    /// The latest release, or nil when it isn't one the updater can install.
    func latestUpdate() async throws -> AppUpdate? {
        var request = URLRequest(url: UpdateParsing.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let data: Data
        do {
            let (body, response) = try await Self.session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                RunLog.write("Update check: GitHub answered \(status)")
                throw UpdateError.network
            }
            data = body
        } catch let error as UpdateError {
            throw error
        } catch {
            if Task.isCancelled { throw UpdateError.cancelled }
            RunLog.write("Update check failed: \(error.localizedDescription)")
            throw UpdateError.network
        }
        do {
            return try UpdateParsing.update(fromReleaseJSON: data)
        } catch {
            RunLog.write("Could not read GitHub's release (\(data.count) bytes): \(error)")
            throw UpdateError.unreadableRelease
        }
    }

    // MARK: Installing

    /// Checks the app is somewhere it can be replaced, before anything is downloaded.
    func checkCanReplaceApp() throws {
        if bundleURL.path.contains("/AppTranslocation/") {
            RunLog.write("Update: the app is translocated, at \(bundleURL.path)")
            throw UpdateError.translocated
        }
        let folder = bundleURL.deletingLastPathComponent().path
        guard FileManager.default.isWritableFile(atPath: folder) else {
            RunLog.write("Update: can't write to \(folder)")
            throw UpdateError.folderNotWritable
        }
    }

    /// Downloads, checks and unpacks the update, then puts it where the running app is.
    /// The app that is running stays in place unless every check passes.
    /// - Parameter progress: Called with the bytes downloaded so far.
    func install(_ update: AppUpdate, progress: @escaping @Sendable (Int64) -> Void) async throws {
        try checkCanReplaceApp()
        let manager = FileManager.default
        // A folder on the app's own volume, so the new app can be moved into place in one step.
        let workFolder: URL
        do {
            workFolder = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: bundleURL, create: true)
        } catch {
            RunLog.write("Update: no folder to work in: \(error.localizedDescription)")
            throw UpdateError.replaceFailed
        }
        defer { try? manager.removeItem(at: workFolder) }

        let zip = workFolder.appendingPathComponent("update.zip")
        try await download(update.downloadURL, to: zip, progress: progress)

        let sha256 = try Self.sha256(ofFileAt: zip)
        guard sha256 == update.sha256 else {
            RunLog.write("Update: checksum is \(sha256), but the release says \(update.sha256)")
            throw UpdateError.checksumMismatch
        }

        let unpacked = workFolder.appendingPathComponent("unpacked")
        try await unpack(zip, into: unpacked)
        let newApp = unpacked.appendingPathComponent(bundleURL.lastPathComponent)
        try verify(newApp, is: update)
        try Task.checkCancellation()

        // Set the running app aside, move the new one in, and put the old one back if that fails.
        let oldApp = workFolder.appendingPathComponent("previous.app")
        do {
            try manager.moveItem(at: bundleURL, to: oldApp)
            do {
                try manager.moveItem(at: newApp, to: bundleURL)
            } catch {
                try? manager.moveItem(at: oldApp, to: bundleURL)
                throw error
            }
        } catch {
            RunLog.write("Update: could not replace \(bundleURL.path): \(error.localizedDescription)")
            throw UpdateError.replaceFailed
        }
        RunLog.write("Update: installed \(update.version) (\(update.build)) at \(bundleURL.path)")
    }

    /// Opens the app that is now at the running app's path. The caller then quits.
    func openInstalledApp() async -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        // Without this, macOS only brings the running copy to the front.
        configuration.createsNewApplicationInstance = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
            return true
        } catch {
            RunLog.write("Update: could not open the new app: \(error.localizedDescription)")
            return false
        }
    }

    private func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        RunLog.write("Update: downloading \(url.absoluteString)")
        let box = TaskBox()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = Self.session.downloadTask(with: url) { file, response, error in
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard let file, error == nil, status == 200 else {
                        if (error as? URLError)?.code == .cancelled {
                            continuation.resume(throwing: UpdateError.cancelled)
                        } else {
                            RunLog.write("Update: download failed, status \(status): \(error?.localizedDescription ?? "no error")")
                            continuation.resume(throwing: UpdateError.downloadFailed)
                        }
                        return
                    }
                    // The file goes when this returns, so it is moved now.
                    do {
                        try FileManager.default.moveItem(at: file, to: destination)
                        continuation.resume()
                    } catch {
                        RunLog.write("Update: could not keep the download: \(error.localizedDescription)")
                        continuation.resume(throwing: UpdateError.downloadFailed)
                    }
                }
                box.start(task, observing: progress)
            }
        } onCancel: {
            box.cancel()
        }
    }

    /// Unpacks the zip with `ditto`, which made it, so symbolic links and permissions survive.
    private func unpack(_ zip: URL, into folder: URL) async throws {
        let arguments = ["-x", "-k", zip.path, folder.path]
        let command = "/usr/bin/ditto \(arguments.joined(separator: " "))"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let err = Pipe()
        process.standardError = err
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                RunLog.write("Run: \(command)")
                do {
                    try process.run()
                } catch {
                    RunLog.write("Could not start: \(command)\n\(error.localizedDescription)")
                    continuation.resume(throwing: UpdateError.unpackFailed)
                    return
                }
                let errorData = err.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let errorOutput = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                RunLog.write("Exit \(process.terminationStatus): \(command)" + (errorOutput.isEmpty ? "" : "\n\(errorOutput)"))
                continuation.resume(returning: process.terminationStatus)
            }
        }
        guard status == 0 else { throw UpdateError.unpackFailed }
    }

    /// Checks the unpacked app is this app, at the build the release promised, and that
    /// nothing in it has changed since it was signed.
    func verify(_ app: URL, is update: AppUpdate) throws {
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        let identifier = info?["CFBundleIdentifier"] as? String
        let build = UpdateParsing.build(fromBundleVersion: info?["CFBundleVersion"])
        guard identifier != nil, identifier == bundleIdentifier, build == update.build else {
            RunLog.write("Update: unpacked \(identifier ?? "nothing") build \(build.map(String.init) ?? "?"), expected \(bundleIdentifier ?? "?") build \(update.build)")
            throw UpdateError.notTheExpectedApp
        }
        var code: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(app as CFURL, [], &code)
        if status == errSecSuccess, let code {
            let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
            status = SecStaticCodeCheckValidity(code, flags, nil)
        }
        guard status == errSecSuccess else {
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
            RunLog.write("Update: the unpacked app's signature is not valid (\(status): \(reason))")
            throw UpdateError.notTheExpectedApp
        }
    }

    /// The SHA-256 of a file, in lowercase hex, read a piece at a time.
    static func sha256(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Holds the download so a cancellation can reach it, and reports its progress.
    private final class TaskBox: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionDownloadTask?
        private var observation: NSKeyValueObservation?
        private var cancelled = false

        func start(_ task: URLSessionDownloadTask, observing progress: @escaping @Sendable (Int64) -> Void) {
            let cancelNow = lock.withLock {
                self.task = task
                observation = task.observe(\.countOfBytesReceived) { task, _ in
                    progress(task.countOfBytesReceived)
                }
                return cancelled
            }
            task.resume()
            if cancelNow {
                task.cancel()
            }
        }

        func cancel() {
            let running = lock.withLock {
                cancelled = true
                return task
            }
            running?.cancel()
        }
    }
}
