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
/// the files are only read, either where Homebrew installed them or from a download
/// that is deleted again once it has been shown.
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

    /// The font file for the details pane to preview a font that isn't installed.
    /// Only this one downloaded font is kept: showing another font removes it.
    static func detailsFile(for font: FontCask) async throws -> URL {
        guard let source = font.previewDownloadURL else { throw FontPreviewError.downloadFailed }
        let kept = cacheDirectory.appendingPathComponent("\(font.token)-\(cacheKey(for: font)).\(source.pathExtension.lowercased())")
        removeDownloads(except: kept)
        if FileManager.default.fileExists(atPath: kept.path) {
            return kept
        }
        let downloaded = try await download(font)
        defer { try? FileManager.default.removeItem(at: downloaded) }
        try Task.checkCancellation()
        // Another font may have been shown, and its file kept, while this one was downloading.
        removeDownloads(except: kept)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: downloaded, to: kept)
        return kept
    }

    /// Deletes the fonts downloaded for the details pane, apart from the one given.
    static func removeDownloads(except kept: URL? = nil) {
        let files = (try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent != kept?.lastPathComponent {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Downloads a font's preview file to a temporary place and checks it.
    /// The caller deletes the file when it has finished with it.
    static func download(_ font: FontCask) async throws -> URL {
        guard let source = font.previewDownloadURL else { throw FontPreviewError.downloadFailed }
        RunLog.write("Download preview for \(font.token): \(source.absoluteString)")
        let downloaded: URL
        let response: URLResponse
        do {
            (downloaded, response) = try await URLSession.shared.download(from: source)
        } catch {
            // A thumbnail that scrolls out of view cancels its download, which isn't worth a log line.
            if !Task.isCancelled {
                RunLog.write("Preview download failed for \(font.token): \(error.localizedDescription)")
            }
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
        // Core Text reads the kind of font from the file's extension, which the download lacks.
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(source.pathExtension.lowercased())")
        try FileManager.default.copyItem(at: downloaded, to: file)
        return file
    }

    /// Changes when the font's version does, so a new version is downloaded again.
    static func cacheKey(for font: FontCask) -> String {
        let digest = SHA256.hash(data: Data("\(font.version) \(font.downloadURL?.absoluteString ?? "")".utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    static let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "HomebrewFontGallery")
        .appendingPathComponent("Previews")
}
