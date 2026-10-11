import Foundation

/// A font the widget can show without installing it: one whose font file downloads by itself.
/// The list of them ships inside the widget as `WidgetFonts.json`.
struct WidgetFont: Codable, Hashable, Identifiable {
    /// Homebrew's name for the font, such as "font-fira-code".
    let token: String
    /// The font's own name, such as "Fira Code".
    let name: String
    let url: URL
    /// The download's SHA-256, or nil when Homebrew doesn't check one.
    let sha256: String?
    /// Google Fonts' category for the font: "Sans Serif", "Serif", "Display", "Handwriting"
    /// or "Monospace". Nil for a font Google Fonts doesn't carry.
    var category: String?

    var id: String { token }

    /// True when the category or the name says the font is meant for code.
    var isMonospaced: Bool {
        if let category { return category == "Monospace" }
        let words = token.lowercased()
        return ["mono", "code", "courier", "consol", "typewriter"].contains { words.contains($0) }
    }

    /// The kind of letters the font has, from its category, or failing that from its name.
    /// Small caps and display cuts are for headings, whatever family they belong to.
    var kind: FontKind {
        let words = Set(name.lowercased().split(separator: " ").map(String.init))
        if !words.isDisjoint(with: ["sc", "display", "caps", "inline", "stencil"]) { return .expressive }
        switch category {
        case "Sans Serif": return .sans
        case "Serif": return .serif
        case .some: return .expressive
        case nil:
            if words.contains("sans") { return .sans }
            if words.contains("serif") || words.contains("slab") { return .serif }
            return .expressive
        }
    }

    static func decodeCatalogue(_ data: Data) throws -> [WidgetFont] {
        try JSONDecoder().decode([WidgetFont].self, from: data)
    }

    static func encodeCatalogue(_ fonts: [WidgetFont]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
        return try encoder.encode(fonts.sorted { $0.token < $1.token })
    }
}

/// The fonts to try for one day, in the order to try them. The same day always gives the
/// same fonts, so the widget shows one set all day however often it is redrawn.
struct DailyFonts: Equatable {
    /// The day as "2026-10-11", in the Mac's own time zone.
    let day: String
    /// Plain sans serif and serif fonts, which can set a paragraph as well as a heading.
    let text: [WidgetFont]
    /// Display and handwriting fonts, for headings.
    let expressive: [WidgetFont]
    /// Monospaced fonts, for the code in the extra large widget.
    let code: [WidgetFont]

    /// More fonts are picked than are shown, because some will fail to download or
    /// turn out to have no Latin letters. Each kind is picked separately, so every day
    /// has plain fonts to pair the expressive ones with.
    static func pick(from catalogue: [WidgetFont], day: String, textCount: Int = 14, expressiveCount: Int = 8,
                     codeCount: Int = 8) -> DailyFonts {
        var generator = SeededGenerator(seed: day)
        // Sorted first, so the order of the catalogue file doesn't change the day's fonts.
        let sorted = catalogue.sorted { $0.token < $1.token }
        let code = sorted.filter(\.isMonospaced).shuffled(using: &generator)
        let text = sorted.filter { !$0.isMonospaced && $0.kind != .expressive }.shuffled(using: &generator)
        let expressive = sorted.filter { !$0.isMonospaced && $0.kind == .expressive }.shuffled(using: &generator)
        return DailyFonts(day: day, text: Array(text.prefix(textCount)),
                          expressive: Array(expressive.prefix(expressiveCount)), code: Array(code.prefix(codeCount)))
    }

    static func day(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// When the next day's fonts take over.
    static func nextDay(after date: Date, calendar: Calendar = .current) -> Date {
        calendar.nextDate(after: date, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime)
            ?? date.addingTimeInterval(24 * 60 * 60)
    }

    /// Turns a count of forward and back presses into a position in a list, going round at either end.
    static func position(_ presses: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((presses % count) + count) % count
    }
}

/// A random number generator that gives the same numbers for the same seed, on every Mac and every launch.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: String) {
        // FNV-1a. Swift's own hashing changes from one launch to the next.
        state = seed.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01b3 }
    }

    mutating func next() -> UInt64 {
        // SplitMix64.
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
}
