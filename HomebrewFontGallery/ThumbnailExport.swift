import AppKit

/// Draws the thumbnail of every font Homebrew offers into a folder, for shipping with the app.
/// It runs when the app is started with `--export-thumbnails <folder>`, which
/// `scripts/update-thumbnails.sh` does, and quits when it has finished.
enum ThumbnailExport {
    private static let argument = "--export-thumbnails"

    /// The folder named on the command line, or nil when the app was opened normally.
    static let directory: URL? = {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }()

    static func run(to directory: URL) {
        Task {
            let succeeded = await export(to: directory)
            exit(succeeded ? EXIT_SUCCESS : EXIT_FAILURE)
        }
    }

    private static func export(to directory: URL) async -> Bool {
        let fonts: [FontCask]
        do {
            fonts = try await BrewService().allFonts().filter { $0.isInstallable || $0.isInstalled }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            print("Could not list the fonts: \(error)")
            return false
        }
        print("Drawing thumbnails for \(fonts.count) fonts into \(directory.path)")

        var drawn = Set<String>()
        await withTaskGroup(of: String?.self) { group in
            var remaining = fonts.makeIterator()
            func addNext() {
                guard let font = remaining.next() else { return }
                group.addTask {
                    guard let data = await FontThumbnails.shared.render(font) else { return nil }
                    let file = directory.appendingPathComponent("\(font.token).png")
                    return (try? data.write(to: file, options: .atomic)) != nil ? font.token : nil
                }
            }
            for _ in 0..<12 { addNext() }
            var finished = 0
            for await token in group {
                if let token { drawn.insert(token) }
                finished += 1
                if finished % 100 == 0 { print("\(finished) of \(fonts.count)") }
                addNext()
            }
        }

        // Drop pictures of fonts that Homebrew no longer offers or that can no longer be drawn.
        let existing = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in existing where file.pathExtension == "png" && !drawn.contains(file.deletingPathExtension().lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
        print("Drew \(drawn.count) thumbnails. \(fonts.count - drawn.count) fonts can only be previewed once installed.")
        return !drawn.isEmpty
    }
}
