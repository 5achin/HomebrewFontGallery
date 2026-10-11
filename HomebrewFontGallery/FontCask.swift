import Foundation

/// One font that Homebrew offers, as described by `brew info --json=v2 --cask`.
struct FontCask: Identifiable, Hashable {
    /// Homebrew's name for the font, such as "font-fira-code".
    let token: String
    /// The font's own name, such as "Fira Code".
    let name: String
    let alternateNames: [String]
    let summary: String?
    let homepage: URL?
    let downloadURL: URL?
    /// The download's SHA-256, or nil when Homebrew doesn't check one.
    let sha256: String?
    let version: String
    /// The version Homebrew has installed, or nil when the font isn't installed.
    let installedVersion: String?
    /// Where Homebrew puts each font file when it installs the font.
    let fontFiles: [URL]
    /// True when the font comes as an installer package, which needs an administrator.
    let needsInstaller: Bool
    let isDeprecated: Bool
    let isDisabled: Bool

    var id: String { token }
    var isInstalled: Bool { installedVersion != nil }

    /// Homebrew can install the font without help: no installer package, and not withdrawn.
    var isInstallable: Bool { !needsInstaller && !isDisabled }

    /// The download itself, when it is a single font file that can be previewed before installing.
    var previewDownloadURL: URL? {
        guard let downloadURL, downloadURL.scheme == "https",
              FontCask.fontFileExtensions.contains(downloadURL.pathExtension.lowercased()) else { return nil }
        return downloadURL
    }

    static let fontFileExtensions: Set<String> = ["ttf", "otf", "ttc", "otc"]
}
