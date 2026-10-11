import Foundation

enum BrewError: Error, Equatable {
    /// `brew` isn't in either of the places Homebrew installs it.
    case notInstalled
    /// `brew` could not be started.
    case launchFailed
    /// `brew` ran and reported a failure.
    case failed(status: Int32)
    /// `brew` succeeded, but its output wasn't what the app expects.
    case unreadableOutput
    case cancelled
}

/// The only type that runs external commands. It launches `brew` directly, with no shell,
/// and writes every command, its exit status and its error output to the run log.
struct BrewService {
    static let searchPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    let executable: String?

    init(executable: String? = BrewService.searchPaths.first { FileManager.default.isExecutableFile(atPath: $0) }) {
        self.executable = executable
    }

    // MARK: Commands

    /// Every font Homebrew offers, with its details and whether it is installed.
    func allFonts() async throws -> [FontCask] {
        let list = try await run(BrewParsing.listAllArguments)
        let tokens = BrewParsing.fontTokens(fromCaskList: String(decoding: list, as: UTF8.self))
        guard !tokens.isEmpty else {
            RunLog.write("brew casks listed no fonts")
            throw BrewError.unreadableOutput
        }
        return try await fonts(tokens: tokens)
    }

    /// The current details of one font, or nil when Homebrew no longer lists it.
    func font(token: String) async throws -> FontCask? {
        try await fonts(tokens: [token]).first { $0.token == token }
    }

    func install(token: String) async throws {
        _ = try await run(BrewParsing.installArguments(token: token))
    }

    func uninstall(token: String) async throws {
        _ = try await run(BrewParsing.uninstallArguments(token: token))
    }

    private func fonts(tokens: [String]) async throws -> [FontCask] {
        let tokens = tokens.filter(BrewParsing.isFontToken)
        guard !tokens.isEmpty else { return [] }
        let data = try await run(BrewParsing.infoArguments(tokens: tokens), logging: tokens.count == 1 ? nil : "\(tokens.count) fonts")
        do {
            return try BrewParsing.fonts(fromInfoJSON: data)
        } catch {
            RunLog.write("Could not read brew info output (\(data.count) bytes): \(error)")
            throw BrewError.unreadableOutput
        }
    }

    // MARK: Running brew

    /// Runs `brew` with the given arguments and returns what it printed.
    /// Cancelling the task interrupts `brew`, as Control-C would, so it can clean up.
    /// - Parameter summary: Stands in for a long argument list in the log.
    private func run(_ arguments: [String], logging summary: String? = nil) async throws -> Data {
        guard let executable else {
            RunLog.write("brew not found in \(BrewService.searchPaths.joined(separator: " or "))")
            throw BrewError.notInstalled
        }
        let logged = summary.map { "\(arguments.prefix(3).joined(separator: " ")) [\($0)]" } ?? arguments.joined(separator: " ")
        let command = "\(executable) \(logged)"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = BrewService.environment
        process.standardInput = FileHandle.nullDevice
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        let cancellation = Cancellation()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    guard !cancellation.isCancelled else {
                        continuation.resume(throwing: BrewError.cancelled)
                        return
                    }
                    RunLog.write("Run: \(command)")
                    let started = Date()
                    do {
                        try process.run()
                    } catch {
                        RunLog.write("Could not start: \(command)\n\(error.localizedDescription)")
                        continuation.resume(throwing: BrewError.launchFailed)
                        return
                    }
                    cancellation.started(process)
                    // Drain both pipes at once, so a full one can't stall brew.
                    var errorData = Data()
                    let reading = DispatchGroup()
                    DispatchQueue.global(qos: .userInitiated).async(group: reading) {
                        errorData = err.fileHandleForReading.readDataToEndOfFile()
                    }
                    let output = out.fileHandleForReading.readDataToEndOfFile()
                    reading.wait()
                    process.waitUntilExit()

                    let status = process.terminationStatus
                    let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
                    let errorOutput = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    var entry = "Exit \(status) after \(seconds) s: \(command)"
                    if !errorOutput.isEmpty {
                        entry += "\n\(errorOutput)"
                    }
                    if status != 0, summary == nil {
                        let printed = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !printed.isEmpty {
                            entry += "\n\(printed)"
                        }
                    }
                    RunLog.write(entry)

                    if cancellation.isCancelled || process.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: BrewError.cancelled)
                    } else if status != 0 {
                        continuation.resume(throwing: BrewError.failed(status: status))
                    } else {
                        continuation.resume(returning: output)
                    }
                }
            }
        } onCancel: {
            RunLog.write("Cancel: \(command)")
            cancellation.cancel()
        }
    }

    /// Carries a cancellation across to the thread running `brew`, whether it arrives
    /// before or after the process starts.
    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        private var process: Process?

        var isCancelled: Bool {
            lock.withLock { cancelled }
        }

        func started(_ process: Process) {
            let interrupt = lock.withLock {
                self.process = process
                return cancelled
            }
            if interrupt {
                process.interrupt()
            }
        }

        func cancel() {
            let running = lock.withLock {
                cancelled = true
                return process
            }
            if let running, running.isRunning {
                running.interrupt()
            }
        }
    }

    /// The app's own environment, with settings that keep brew's output plain.
    private static let environment: [String: String] = {
        var environment = ProcessInfo.processInfo.environment
        environment["HOMEBREW_NO_COLOR"] = "1"
        environment["HOMEBREW_NO_EMOJI"] = "1"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        environment["HOMEBREW_NO_ANALYTICS_MESSAGE_OUTPUT"] = "1"
        return environment
    }()
}
