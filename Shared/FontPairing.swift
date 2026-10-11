import Foundation

/// What kind of letters a font has, as far as pairing it with another font goes.
enum FontKind: String, Codable {
    /// A plain sans serif, fit for running text.
    case sans
    /// A plain serif or slab serif, fit for running text.
    case serif
    /// A display or handwriting font, or one nothing is known about: fit for headings only.
    case expressive
}

/// What can be measured from a font's file, in units that compare between fonts.
struct FontTraits: Codable, Hashable {
    var kind: FontKind
    /// The height of a lowercase x over the height of a capital H. About 0.7 for most text fonts.
    var xHeight: Double
    /// The average width of a lowercase letter over the font's size. About 0.5 for most text fonts.
    var width: Double
    /// Core Text's weight, from -1 (thinnest) through 0 (regular) to 1 (heaviest).
    var weight: Double
}

/// One heading, paragraph and code font to show together.
struct FontCombination: Codable, Hashable {
    let heading: String
    let paragraph: String
    let code: String?
}

/// Chooses fonts that go together, following the usual advice on pairing type:
///
/// 1. Give each font a clear job. A paragraph needs a plain text face of ordinary weight,
///    width and proportions. Anything may be a heading.
/// 2. Pair by contrast, not near-likeness: a serif with a sans, or an expressive heading over
///    plain text. Two fonts of the same kind that differ only a little look like a mistake.
/// 3. Under the contrast, share a skeleton: the lowercase should be about as tall and as wide
///    in both, so the two sit together at the same size.
/// 4. Fonts drawn as one family ("Noto Sans" with "Noto Serif") are already matched.
/// 5. Code takes the monospaced font whose lowercase is closest in height to the paragraph's.
enum FontPairing {
    struct Candidate: Hashable {
        let token: String
        let name: String
        let traits: FontTraits
    }

    /// True when the font is plain enough to set a paragraph in.
    static func suitsParagraphs(_ traits: FontTraits) -> Bool {
        traits.kind != .expressive
            && (0.58...0.80).contains(traits.xHeight)
            && (0.42...0.62).contains(traits.width)
            && (-0.25...0.25).contains(traits.weight)
    }

    /// How well a heading font goes over a paragraph font, from 0 to 1.
    static func score(heading: Candidate, paragraph: Candidate) -> Double {
        guard heading.token != paragraph.token, suitsParagraphs(paragraph.traits) else { return 0 }
        if family(of: heading.name) == family(of: paragraph.name) {
            return 1
        }
        let contrast: Double
        if heading.traits.kind == .expressive {
            contrast = 0.85
        } else if heading.traits.kind != paragraph.traits.kind {
            contrast = 1
        } else {
            // The same kind of letter twice only works when the heading is clearly heavier.
            contrast = heading.traits.weight - paragraph.traits.weight > 0.2 ? 0.45 : 0.15
        }
        let height = closeness(heading.traits.xHeight, paragraph.traits.xHeight, within: 0.15)
        let width = closeness(heading.traits.width, paragraph.traits.width, within: 0.15)
        return 0.5 * contrast + 0.3 * height + 0.2 * width
    }

    /// The best combinations to show, best first. Each font heads at most one of them,
    /// and no font carries the paragraphs of more than two, so the day shows some variety.
    /// Only on a day with too few paragraph fonts to go round does one carry more.
    static func combinations(text: [Candidate], code: [Candidate], limit: Int) -> [FontCombination] {
        var pairs: [(heading: Candidate, paragraph: Candidate, score: Double)] = []
        for heading in text {
            for paragraph in text {
                let score = score(heading: heading, paragraph: paragraph)
                if score > 0 {
                    pairs.append((heading, paragraph, score))
                }
            }
        }
        // Ties are settled by name, so the same fonts always give the same combinations.
        pairs.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.heading.token != $1.heading.token { return $0.heading.token < $1.heading.token }
            return $0.paragraph.token < $1.paragraph.token
        }

        var chosen: [FontCombination] = []
        var headings = Set<String>()
        var paragraphs: [String: Int] = [:]
        for most in [2, Int.max] {
            for pair in pairs where chosen.count < limit {
                guard !headings.contains(pair.heading.token), paragraphs[pair.paragraph.token, default: 0] < most else { continue }
                // The same two fonts the other way round would be a repeat, while there are others to show.
                let mirrored = chosen.contains { $0.heading == pair.paragraph.token && $0.paragraph == pair.heading.token }
                if mirrored, most == 2 { continue }
                headings.insert(pair.heading.token)
                paragraphs[pair.paragraph.token, default: 0] += 1
                chosen.append(FontCombination(heading: pair.heading.token, paragraph: pair.paragraph.token,
                                              code: codeFont(for: pair.paragraph, from: code)?.token))
            }
        }
        return chosen
    }

    /// The monospaced font whose lowercase is closest in height to the paragraph's.
    static func codeFont(for paragraph: Candidate, from code: [Candidate]) -> Candidate? {
        code.min {
            let first = abs($0.traits.xHeight - paragraph.traits.xHeight)
            let second = abs($1.traits.xHeight - paragraph.traits.xHeight)
            return first != second ? first < second : $0.token < $1.token
        }
    }

    /// "Noto Serif Display" and "Noto Sans" are both of the family "noto".
    static func family(of name: String) -> String {
        let styles: Set<String> = ["sans", "serif", "slab", "mono", "code", "display", "text", "condensed", "sc", "pro"]
        let words = name.lowercased().split(separator: " ").map(String.init)
        let end = words.firstIndex(where: styles.contains) ?? words.count
        return words[..<max(end, 1)].joined(separator: " ")
    }

    /// 1 when the two values are the same, falling to 0 when they are `within` apart or more.
    private static func closeness(_ first: Double, _ second: Double, within range: Double) -> Double {
        max(0, 1 - abs(first - second) / range)
    }
}
