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
    /// Each font file's path inside the download, in the same order as `fontFiles`.
    let sourceFiles: [String]
    /// Set when Homebrew takes the font from one folder of a git repository.
    let repositoryFolder: RepositoryFolder?
    /// True when the font comes as an installer package, which needs an administrator.
    let needsInstaller: Bool
    let isDeprecated: Bool
    let isDisabled: Bool

    var id: String { token }
    var isInstalled: Bool { installedVersion != nil }

    /// Homebrew can install the font without help: no installer package, and not withdrawn.
    var isInstallable: Bool { !needsInstaller && !isDisabled }

    /// A single font file that can be downloaded to preview the font before installing it:
    /// the download itself, or one file of a font that Homebrew takes from a folder on GitHub.
    var previewDownloadURL: URL? {
        guard let downloadURL, downloadURL.scheme == "https" else { return nil }
        if FontCask.fontFileExtensions.contains(downloadURL.pathExtension.lowercased()) {
            return downloadURL
        }
        guard downloadURL.host() == "github.com", downloadURL.pathExtension == "git",
              let folder = repositoryFolder, let file = FontCask.representativeFile(in: sourceFiles) else { return nil }
        let path = ([folder.branch] + folder.path.split(separator: "/").map(String.init) + file.split(separator: "/").map(String.init))
        guard !path.contains(".."), !path.contains("") else { return nil }
        return path.reduce(downloadURL.deletingPathExtension().appendingPathComponent("raw")) { $0.appendingPathComponent($1) }
    }

    /// The file most likely to hold the regular style: "…-Regular.ttf", then an upright variable font.
    static func representativeFile(in files: [String]) -> String? {
        let fonts = files.filter { fontFileExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
        return fonts.first { $0.localizedCaseInsensitiveContains("Regular") }
            ?? fonts.first { !$0.localizedCaseInsensitiveContains("Italic") }
            ?? fonts.first
    }

    struct RepositoryFolder: Hashable {
        let branch: String
        let path: String
    }

    static let fontFileExtensions: Set<String> = ["ttf", "otf", "ttc", "otc"]
}
