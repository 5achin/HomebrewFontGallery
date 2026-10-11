import Foundation

/// A build of the app published on GitHub that the updater can download and install.
struct AppUpdate: Equatable {
    /// The marketing version, such as "1.0".
    let version: String
    /// The build number, which is the number of the workflow run that published it.
    let build: Int
    let downloadURL: URL
    /// The SHA-256 of the zip that GitHub recorded when the release was published, in lowercase hex.
    let sha256: String
    /// The size of the zip in bytes.
    let size: Int
}

/// Reads GitHub's description of the latest release. Pure functions, covered by unit tests.
enum UpdateParsing {
    static let repository = "5achin/HomebrewFontGallery"
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!

    /// The build number Xcode gives a build made on this Mac. The release workflow replaces
    /// it with its run number, so a build with this number didn't come from a release.
    static let localBuild = 1

    /// Splits a release tag such as "v1.0-build.37" into its version and build number.
    /// Any other tag, such as a plain "v1.0", has no build number to compare and gives nil.
    static func version(fromTag tag: String) -> (version: String, build: Int)? {
        guard let match = tag.wholeMatch(of: /v([0-9]+(?:\.[0-9]+)*)-build\.([0-9]{1,9})/),
              let build = Int(match.2) else { return nil }
        return (String(match.1), build)
    }

    /// The update a release offers, or nil when the release isn't one the updater can install:
    /// a draft or prerelease, a tag without a build number, or no zip with a checksum.
    /// Throws when the data isn't a GitHub release at all.
    static func update(fromReleaseJSON data: Data) throws -> AppUpdate? {
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard !release.draft, !release.prerelease,
              let parsed = version(fromTag: release.tag_name),
              let asset = release.assets.first(where: { $0.name == "HomebrewFontGallery-\(release.tag_name).zip" }),
              let url = URL(string: asset.browser_download_url), isReleaseDownload(url),
              let sha256 = sha256(fromDigest: asset.digest) else { return nil }
        return AppUpdate(version: parsed.version, build: parsed.build, downloadURL: url, sha256: sha256, size: asset.size)
    }

    /// True only for a secure link to a file in this app's own releases on GitHub.
    static func isReleaseDownload(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.user == nil && url.port == nil
            && url.path.hasPrefix("/\(repository)/releases/download/")
    }

    /// The hex of a digest GitHub reports as "sha256:…", or nil for anything else.
    static func sha256(fromDigest digest: String?) -> String? {
        guard let digest, let match = digest.wholeMatch(of: /sha256:([0-9a-fA-F]{64})/) else { return nil }
        return match.1.lowercased()
    }

    /// The build number in an Info.plist's CFBundleVersion.
    static func build(fromBundleVersion version: Any?) -> Int? {
        (version as? String).flatMap(Int.init)
    }

    private struct Release: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }

    private struct Asset: Decodable {
        let name: String
        let browser_download_url: String
        let size: Int
        let digest: String?
    }
}
