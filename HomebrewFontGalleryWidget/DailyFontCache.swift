import CoreText
import CryptoKit
import Foundation
import os

/// A font file the widget has downloaded and can draw with.
struct CachedFont: Codable, Hashable {
    let token: String
    let name: String
    /// The file's name inside the day's folder.
    let file: String
    let postScriptName: String
    let traits: FontTraits
}

/// The fonts in use for one day, as recorded beside their files.
struct CachedDay: Codable, Hashable {
    let day: String
    var text: [CachedFont]
    var code: [CachedFont]
    /// The fonts to show together in the extra large widget, best matched first.
    var combinations: [FontCombination]

    static let empty = CachedDay(day: "", text: [], code: [], combinations: [])

    func font(_ token: String?) -> CachedFont? {
        guard let token else { return nil }
        return (text + code).first { $0.token == token }
    }
}

/// Keeps the day's fonts in the widget's own cache folder. The first drawing of the day
/// downloads them, every later one reads them from disk, and the day before's are removed.
/// Nothing here installs a font: the files are only read to draw the widget.
enum DailyFontCache {
    /// How many plain fonts, and how many expressive ones, to keep for the day.
    static let textCount = 6
    static let expressiveCount = 6
    static let codeCount = 4
    static let combinationCount = 8
    /// Larger files are mostly fonts for Chinese, Japanese and Korean, which the samples don't suit.
    static let maximumDownloadSize = 4 << 20

    private static let log = Logger(subsystem: "com.sachinkharady.HomebrewFontGallery.Widget", category: "fonts")
    private static let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DailyFonts")
    private static let manifestName = "fonts.json"

    static func folder(for day: String) -> URL {
        root.appendingPathComponent(day)
    }

    /// The fonts for the day, downloading them if this is the day's first drawing.
    /// When they can't be downloaded, the last set that was downloaded is shown instead.
    static func fonts(for day: String) async -> CachedDay {
        if let cached = read(day) {
            return cached
        }
        guard let url = Bundle.main.url(forResource: "WidgetFonts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalogue = try? WidgetFont.decodeCatalogue(data) else {
            log.error("The list of fonts is missing from the widget.")
            return latest() ?? .empty
        }
        let picked = DailyFonts.pick(from: catalogue, day: day)
        let folder = folder(for: day)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        async let plain = download(picked.text, monospaced: false, into: folder)
        async let expressive = download(picked.expressive, monospaced: false, into: folder)
        async let monospaced = download(picked.code, monospaced: true, into: folder)
        // Plain fonts that can set a paragraph are kept first, so the day has enough of them to pair with.
        let suited = await plain.filter { FontPairing.suitsParagraphs($0.traits) }
        let unsuited = await plain.filter { !FontPairing.suitsParagraphs($0.traits) }
        let text = interleave(Array((suited + unsuited).prefix(textCount)), Array(await expressive.prefix(expressiveCount)))
        let code = Array(await monospaced.prefix(codeCount))
        let fetched = CachedDay(day: day, text: text, code: code,
                                combinations: FontPairing.combinations(text: text.map(\.candidate), code: code.map(\.candidate),
                                                                       limit: combinationCount))
        guard !fetched.text.isEmpty else {
            log.error("None of the fonts for \(day, privacy: .public) could be downloaded.")
            try? FileManager.default.removeItem(at: folder)
            return latest() ?? .empty
        }
        removeFiles(in: folder, notUsedBy: fetched)
        if let manifest = try? JSONEncoder().encode(fetched) {
            try? manifest.write(to: folder.appendingPathComponent(manifestName), options: .atomic)
        }
        removeDays(except: day)
        return fetched
    }

    /// Takes from each list in turn, so the back and forward buttons alternate between the kinds.
    private static func interleave(_ first: [CachedFont], _ second: [CachedFont]) -> [CachedFont] {
        (0..<max(first.count, second.count)).flatMap { index in
            [first, second].compactMap { $0.indices.contains(index) ? $0[index] : nil }
        }
    }

    private static func read(_ day: String) -> CachedDay? {
        let folder = folder(for: day)
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(manifestName)),
              let cached = try? JSONDecoder().decode(CachedDay.self, from: data),
              !cached.text.isEmpty,
              (cached.text + cached.code).allSatisfy({ FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.file).path) })
        else { return nil }
        return cached
    }

    /// The newest day that finished downloading.
    private static func latest() -> CachedDay? {
        let days = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return days.sorted().reversed().lazy.compactMap(read).first
    }

    private static func removeDays(except day: String) {
        let days = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        for other in days where other != day {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(other))
        }
    }

    private static func removeFiles(in folder: URL, notUsedBy day: CachedDay) {
        let used = Set((day.text + day.code).map(\.file))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for file in files where !used.contains(file) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        }
    }

    /// Downloads the fonts side by side and returns the ones that arrived, in the order given.
    private static func download(_ fonts: [WidgetFont], monospaced: Bool, into folder: URL) async -> [CachedFont] {
        await withTaskGroup(of: (Int, CachedFont?).self) { group in
            for (index, font) in fonts.enumerated() {
                group.addTask { (index, await download(font, monospaced: monospaced, into: folder)) }
            }
            var arrived: [(Int, CachedFont)] = []
            for await (index, font) in group {
                if let font { arrived.append((index, font)) }
            }
            return arrived.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private static func download(_ font: WidgetFont, monospaced: Bool, into folder: URL) async -> CachedFont? {
        guard font.url.scheme == "https" else { return nil }
        var request = URLRequest(url: font.url)
        request.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            log.error("Could not download \(font.token, privacy: .public).")
            return nil
        }
        guard data.count <= maximumDownloadSize else { return nil }
        if let expected = font.sha256 {
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual == expected else {
                log.error("\(font.token, privacy: .public) has SHA-256 \(actual, privacy: .public), expected \(expected, privacy: .public).")
                return nil
            }
        }
        // Core Text reads the kind of font from the file's extension.
        let name = "\(font.token).\(font.url.pathExtension.lowercased())"
        let file = folder.appendingPathComponent(name)
        guard (try? data.write(to: file, options: .atomic)) != nil,
              let measured = FontFiles.measure(file, kind: font.kind, monospaced: monospaced) else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        return CachedFont(token: font.token, name: font.name, file: name, postScriptName: measured.postScriptName,
                          traits: measured.traits)
    }
}

extension CachedFont {
    var candidate: FontPairing.Candidate {
        FontPairing.Candidate(token: token, name: name, traits: traits)
    }
}

enum FontFiles {
    /// The name and measurements of the first style in the file, or nil when the file isn't
    /// a font or has no Latin letters to draw the samples with. A font wanted for code must
    /// also give every letter the same width, whatever its name suggests.
    static func measure(_ file: URL, kind: FontKind, monospaced: Bool) -> (postScriptName: String, traits: FontTraits)? {
        guard let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor])?.first,
              let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String else { return nil }
        let size = 100.0
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        let letters = Array("AaBbGgQqRr0123".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: letters.count)
        guard CTFontGetGlyphsForCharacters(font, letters, &glyphs, letters.count) else { return nil }
        if monospaced {
            var advances = [CGSize](repeating: .zero, count: glyphs.count)
            CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)
            guard advances.allSatisfy({ abs($0.width - advances[0].width) < 0.01 }) else { return nil }
        }

        // The letters' own outlines are measured, as the heights a font declares are often wrong.
        let capHeight = height(of: "H", in: font)
        let lowercase = Array("abcdefghijklmnopqrstuvwxyz".utf16)
        var lowercaseGlyphs = [CGGlyph](repeating: 0, count: lowercase.count)
        guard capHeight > 0, CTFontGetGlyphsForCharacters(font, lowercase, &lowercaseGlyphs, lowercase.count) else { return nil }
        let advance = CTFontGetAdvancesForGlyphs(font, .horizontal, lowercaseGlyphs, nil, lowercaseGlyphs.count)
        let weight = (CTFontCopyTraits(font) as? [CFString: Any])?[kCTFontWeightTrait] as? Double ?? 0
        let traits = FontTraits(kind: kind, xHeight: height(of: "x", in: font) / capHeight,
                                width: advance / Double(lowercase.count) / size, weight: weight)
        return (name, traits)
    }

    private static func height(of letter: Character, in font: CTFont) -> Double {
        let characters = Array(String(letter).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        guard CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count) else { return 0 }
        return CTFontGetBoundingRectsForGlyphs(font, .horizontal, glyphs, nil, glyphs.count).maxY
    }

    /// Makes the font usable by name in this process. Registering one twice does no harm.
    static func register(_ file: URL) {
        CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
    }
}
