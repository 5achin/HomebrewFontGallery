import Foundation

/// Writes the list of fonts the widget chooses from, for shipping inside the widget.
/// It runs when the app is started with `--export-widget-fonts <file>`, which
/// `scripts/update-widget-fonts.sh` does, and quits when it has finished.
enum WidgetFontExport {
    private static let argument = "--export-widget-fonts"

    /// The file named on the command line, or nil when the app was opened normally.
    static let file: URL? = {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }()

    static func run(to file: URL) {
        Task {
            do {
                let fonts = catalogue(from: try await BrewService().allFonts())
                try WidgetFont.encodeCatalogue(fonts).write(to: file, options: .atomic)
                print("Wrote \(fonts.count) fonts to \(file.path)")
                exit(EXIT_SUCCESS)
            } catch {
                print("Could not list the fonts: \(error)")
                exit(EXIT_FAILURE)
            }
        }
    }

    /// The fonts whose file can be downloaded by itself, which is all the widget can fetch.
    /// Noto's fonts for one script each are left out: there are some two hundred of them,
    /// and their Latin letters, which are all the samples show, look alike.
    /// So are barcode fonts, which draw bars in place of letters.
    static func catalogue(from fonts: [FontCask]) -> [WidgetFont] {
        fonts.compactMap { font in
            guard font.isInstallable, !font.isDeprecated, let url = font.previewDownloadURL else { return nil }
            if font.token.hasPrefix("font-noto-"), !notoFamilies.contains(font.token) { return nil }
            if font.token.contains("barcode") { return nil }
            return WidgetFont(token: font.token, name: font.name, url: url, sha256: font.sha256)
        }
    }

    private static let notoFamilies: Set<String> = [
        "font-noto-sans", "font-noto-serif", "font-noto-sans-mono", "font-noto-sans-display", "font-noto-serif-display",
    ]
}
