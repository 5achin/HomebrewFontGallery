import Foundation

/// A group of fonts that share a word in their names, such as "Sans" or "Mono".
struct FontCategory: Identifiable, Hashable {
    /// The word as most fonts write it.
    let word: String
    /// How many fonts have the word anywhere in their name.
    let count: Int

    var id: String { word.lowercased() }

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
            .map { key, _ in
                let word = spellings[key]?.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key ?? key
                return FontCategory(word: word, count: fonts.filter { contains($0, word: key) }.count)
            }
    }

    func contains(_ font: FontCask) -> Bool {
        FontCategory.contains(font, word: id)
    }

    /// True when the word is one of the words of the font's name, whatever its case.
    private static func contains(_ font: FontCask, word: String) -> Bool {
        words(in: font.name).contains { $0.lowercased() == word }
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
