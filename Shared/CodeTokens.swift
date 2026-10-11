import Foundation

/// Splits a sample of Swift into the pieces the widget colours differently.
/// It knows only what the sample needs: it is not a Swift parser.
enum CodeTokens {
    enum Kind: Equatable {
        case plain, keyword, type, string, number, comment
    }

    struct Token: Equatable {
        let text: String
        let kind: Kind
    }

    static let keywords: Set<String> = [
        "struct", "enum", "func", "let", "var", "for", "in", "if", "else", "guard", "return", "import",
        "static", "case", "switch", "while", "true", "false", "nil", "self", "where", "extension", "private",
    ]

    /// The pieces in order. Joined back together they give the code unchanged.
    static func tokens(in code: String) -> [Token] {
        var tokens: [Token] = []
        var plain = ""
        func add(_ text: String, _ kind: Kind) {
            if !plain.isEmpty {
                tokens.append(Token(text: plain, kind: .plain))
                plain = ""
            }
            tokens.append(Token(text: text, kind: kind))
        }

        let characters = Array(code)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            var end = index + 1
            if character == "/", end < characters.count, characters[end] == "/" {
                while end < characters.count, characters[end] != "\n" { end += 1 }
                add(String(characters[index..<end]), .comment)
            } else if character == "\"" {
                while end < characters.count, characters[end] != "\"", characters[end] != "\n" {
                    end += characters[end] == "\\" ? 2 : 1
                }
                end = min(end, characters.count)
                if end < characters.count, characters[end] == "\"" { end += 1 }
                add(String(characters[index..<end]), .string)
            } else if character.isNumber {
                while end < characters.count, characters[end].isNumber || characters[end] == "." { end += 1 }
                add(String(characters[index..<end]), .number)
            } else if character.isLetter || character == "_" {
                while end < characters.count, characters[end].isLetter || characters[end].isNumber || characters[end] == "_" { end += 1 }
                let word = String(characters[index..<end])
                if keywords.contains(word) {
                    add(word, .keyword)
                } else if word.first?.isUppercase == true {
                    add(word, .type)
                } else {
                    plain += word
                }
            } else {
                plain.append(character)
            }
            index = end
        }
        if !plain.isEmpty {
            tokens.append(Token(text: plain, kind: .plain))
        }
        return tokens
    }
}
