import CoreText
import CryptoKit
import Foundation

/// One style inside a font file, such as "Fira Code Bold".
struct FontFace: Identifiable, Equatable {
    let id: String
    let name: String
    let descriptor: CTFontDescriptor

    static func == (lhs: FontFace, rhs: FontFace) -> Bool {
        lhs.id == rhs.id
    }

    func font(size: CGFloat) -> CTFont {
        CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }
}

enum FontPreviewError: Error {
    case downloadFailed
    case checksumMismatch
    case tooLarge
}

/// Reads font files for previewing. Nothing here installs or registers a font:
/// the files are only read, either where Homebrew installed them or from the app's cache.
enum FontPreview {
    static let maximumDownloadSize = 50 << 20

    /// The styles in the given font files, with the regular style first.
    static func faces(in files: [URL]) -> [FontFace] {
        var seen = Set<String>()
        var faces: [FontFace] = []
        for file in files where FileManager.default.isReadableFile(atPath: file.path) {
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor] else { continue }
            for descriptor in descriptors {
                let postScriptName = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String ?? file.lastPathComponent
                let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontDisplayNameAttribute) as? String ?? postScriptName
                guard seen.insert(postScriptName).inserted else { continue }
                faces.append(FontFace(id: postScriptName, name: name, descriptor: descriptor))
            }
        }
        return named(faces).sorted { lhs, rhs in
            let ranks = (regularRank(lhs), regularRank(rhs))
            if ranks.0 != ranks.1 { return ranks.0 < ranks.1 }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Names each face by its style alone ("Bold Italic") when that is enough to tell the faces apart.
    private static func named(_ faces: [FontFace]) -> [FontFace] {
        let styles = faces.map { CTFontDescriptorCopyAttribute($0.descriptor, kCTFontStyleNameAttribute) as? String ?? "" }
        guard !styles.contains(""), Set(styles).count == styles.count else { return faces }
        return zip(faces, styles).map { FontFace(id: $0.id, name: $1, descriptor: $0.descriptor) }
    }

    private static func regularRank(_ face: FontFace) -> Int {
        let style = CTFontDescriptorCopyAttribute(face.descriptor, kCTFontStyleNameAttribute) as? String
        return style == "Regular" ? 0 : 1
    }

    /// The font file to preview a font that isn't installed, downloading it once into the cache.
    static func downloadedFile(for font: FontCask) async throws -> URL {
        guard let source = font.previewDownloadURL else { throw FontPreviewError.downloadFailed }
        let cached = cacheDirectory.appendingPathComponent("\(font.token)-\(cacheKey(for: font)).\(source.pathExtension.lowercased())")
        if FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        RunLog.write("Download preview for \(font.token): \(source.absoluteString)")
        let downloaded: URL
        let response: URLResponse
        do {
            (downloaded, response) = try await URLSession.shared.download(from: source)
        } catch {
            RunLog.write("Preview download failed for \(font.token): \(error.localizedDescription)")
            throw FontPreviewError.downloadFailed
        }
        defer { try? FileManager.default.removeItem(at: downloaded) }

        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            RunLog.write("Preview download failed for \(font.token): HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            throw FontPreviewError.downloadFailed
        }
        let data = try Data(contentsOf: downloaded, options: .mappedIfSafe)
        guard data.count <= maximumDownloadSize else {
            RunLog.write("Preview download for \(font.token) is too large: \(data.count) bytes")
            throw FontPreviewError.tooLarge
        }
        if let expected = font.sha256 {
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual == expected else {
                RunLog.write("Preview download for \(font.token) has SHA-256 \(actual), expected \(expected)")
                throw FontPreviewError.checksumMismatch
            }
        }
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: cached)
        try FileManager.default.copyItem(at: downloaded, to: cached)
        return cached
    }

    /// Changes when the font's version does, so a new version is downloaded again.
    private static func cacheKey(for font: FontCask) -> String {
        let digest = SHA256.hash(data: Data("\(font.version) \(font.downloadURL?.absoluteString ?? "")".utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    static let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "HomebrewFontGallery")
        .appendingPathComponent("Previews")
}
