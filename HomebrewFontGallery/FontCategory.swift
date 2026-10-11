import Foundation

/// A group of fonts whose names end in the same word, such as "Sans" or "Mono".
struct FontCategory: Identifiable, Hashable {
    /// The word as most fonts write it.
    let word: String
    /// How many fonts' names end in the word.
    let count: Int

    var id: String { word.lowercased() }

    /// An SF Symbol for the sidebar. Words without one of their own get the plain text symbol.
    var symbolName: String {
        switch id {
        case "one": return "1.circle"
        case "sans": return "textformat"
        case "mono", "code": return "chevron.left.forwardslash.chevron.right"
        case "guides": return "pencil.line"
        case "sc", "tc", "jp", "kr": return "character.textbox"
        case "script": return "scribble.variable"
        case "display": return "textformat.size.larger"
        case "condensed": return "arrow.right.and.line.vertical.and.arrow.left"
        case "serif", "slab": return "textformat.abc"
        default: return "textformat"
        }
    }

    /// The most common last words of the fonts' names, most common first.
    static func top(_ limit: Int, in fonts: [FontCask]) -> [FontCategory] {
        var endings: [String: Int] = [:]
        var spellings: [String: [String: Int]] = [:]
        for font in fonts {
            guard let last = words(in: font.name).last, isCategoryWord(last) else { continue }
            endings[last.lowercased(), default: 0] += 1
            spellings[last.lowercased(), default: [:]][last, default: 0] += 1
        }
        return endings
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map { key, count in
                let word = spellings[key]?.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key ?? key
                return FontCategory(word: word, count: count)
            }
    }

    /// True when the font's name ends in the category's word, whatever its case.
    func contains(_ font: FontCask) -> Bool {
        FontCategory.words(in: font.name).last?.lowercased() == id
    }

    /// "Literation Nerd Font (Liberation Mono)" becomes its five words, without the brackets.
    static func words(in name: String) -> [String] {
        name.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Single letters and bare numbers ("Noto Sans 2") say nothing about the kind of font.
    private static func isCategoryWord(_ word: String) -> Bool {
        word.count > 1 && word.contains(where: \.isLetter)
    }
}
