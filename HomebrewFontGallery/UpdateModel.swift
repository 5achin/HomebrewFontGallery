import AppKit
import Observation

/// Looks for a newer build of the app when it opens and once a day after that, and installs
/// one when asked. `phase` is what the update sheet shows; nil means there is nothing to show.
@MainActor
@Observable
final class UpdateModel {
    static let shared = UpdateModel()

    enum Phase: Equatable {
        /// Only after Check for Updates… is chosen. The daily check is silent.
        case checking
        case upToDate
        case available(AppUpdate)
        case downloading(AppUpdate, received: Int64)
        case installing(AppUpdate)
        case failed(title: String, message: String)
    }

    private(set) var phase: Phase?

    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    let currentBuild = UpdateParsing.build(fromBundleVersion: Bundle.main.infoDictionary?["CFBundleVersion"]) ?? UpdateParsing.localBuild

    private let service = UpdateService()
    private var task: Task<Void, Never>?
    private var schedule: Task<Void, Never>?

    // MARK: Checking

    /// Checks now and every 24 hours, and says something only when there is an update.
    /// A build made on this Mac isn't a release, so it is left alone.
    func startAutomaticChecks() {
        guard schedule == nil, currentBuild != UpdateParsing.localBuild else { return }
        schedule = Task {
            while !Task.isCancelled {
                await checkQuietly()
                // On the wall clock, so time spent asleep counts towards the day.
                try? await Task.sleep(until: .now + .seconds(24 * 60 * 60), clock: .continuous)
            }
        }
    }

    private func checkQuietly() async {
        guard phase == nil, let update = try? await service.latestUpdate(), phase == nil else { return }
        RunLog.write("Update check: latest is build \(update.build), this is build \(currentBuild)")
        if update.build > currentBuild {
            phase = .available(update)
        }
    }

    /// For Check for Updates…, which always answers.
    func checkNow() {
        guard phase == nil else { return }
        phase = .checking
        task = Task {
            do {
                let update = try await service.latestUpdate()
                guard phase == .checking else { return }
                RunLog.write("Update check: latest is build \(update.map { String($0.build) } ?? "none"), this is build \(currentBuild)")
                if let update, update.build > currentBuild {
                    phase = .available(update)
                } else {
                    phase = .upToDate
                }
            } catch {
                guard phase == .checking else { return }
                phase = Self.failure(for: error as? UpdateError ?? .network)
            }
        }
    }

    // MARK: Installing

    func install(_ update: AppUpdate) {
        guard phase == .available(update) else { return }
        phase = .downloading(update, received: 0)
        task = Task {
            do {
                try await service.install(update) { received in
                    Task { @MainActor in
                        // Whole percents only, so the sheet isn't redrawn for every packet.
                        guard case .downloading(update, let shown) = self.phase,
                              received == Int64(update.size) || (received - shown) * 100 >= Int64(update.size) else { return }
                        self.phase = .downloading(update, received: received)
                    }
                }
            } catch {
                // Cancel has already put the sheet away.
                if let error = error as? UpdateError, error != .cancelled {
                    phase = Self.failure(for: error)
                }
                return
            }
            phase = .installing(update)
            if await service.openInstalledApp() {
                NSApp.terminate(nil)
            } else {
                phase = .failed(
                    title: "The Update Is Installed",
                    message: "Homebrew Fonts Gallery couldn’t reopen itself. Quit it and open it again to use the new version."
                )
            }
        }
    }

    /// Stops a check or a download. Nothing has been changed by then.
    func cancel() {
        task?.cancel()
        dismiss()
    }

    func dismiss() {
        if case .installing = phase { return }
        phase = nil
    }

    // MARK: Messages

    nonisolated static func failure(for error: UpdateError) -> Phase {
        let untouched = "The version you have is unchanged."
        switch error {
        case .network, .unreadableRelease:
            return .failed(
                title: "Couldn’t Check for Updates",
                message: "Check your internet connection and try again."
            )
        case .downloadFailed:
            return .failed(
                title: "Couldn’t Download the Update",
                message: "Check your internet connection and try again. \(untouched)"
            )
        case .checksumMismatch, .unpackFailed, .notTheExpectedApp:
            return .failed(
                title: "The Update Couldn’t Be Verified",
                message: "The download didn’t match the published release, so it wasn’t installed. \(untouched) Try again later."
            )
        case .translocated:
            return .failed(
                title: "Move the App to Update It",
                message: "Homebrew Fonts Gallery can’t replace itself where it is. Quit it, drag it to your Applications folder, open it from there, then check for updates again."
            )
        case .folderNotWritable:
            return .failed(
                title: "Couldn’t Install the Update",
                message: "You don’t have permission to change the folder Homebrew Fonts Gallery is in. Move the app to your Applications folder, then check for updates again."
            )
        case .replaceFailed, .cancelled:
            return .failed(
                title: "Couldn’t Install the Update",
                message: "\(untouched) Choose Help > Show Logs in Finder for details."
            )
        }
    }
}
