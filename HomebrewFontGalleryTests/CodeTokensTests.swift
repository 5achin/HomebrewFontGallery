import XCTest
@testable import HomebrewFontGallery

final class CodeTokensTests: XCTestCase {
    private func kinds(_ code: String) -> [String: CodeTokens.Kind] {
        Dictionary(CodeTokens.tokens(in: code).map { ($0.text, $0.kind) }, uniquingKeysWith: { first, _ in first })
    }

    func testTokensJoinBackIntoTheCode() {
        let code = "// A font.\nstruct Sample {\n    let name = \"Fira \\\"Code\\\"\"\n    var size = 12.5\n}\n"
        XCTAssertEqual(CodeTokens.tokens(in: code).map(\.text).joined(), code)
    }

    func testEachKindIsRecognised() {
        let found = kinds("// A font.\nstruct Sample {\n    let name = \"Fira Code\"\n    var size = 12.5\n}")
        XCTAssertEqual(found["// A font."], .comment)
        XCTAssertEqual(found["struct"], .keyword)
        XCTAssertEqual(found["let"], .keyword)
        XCTAssertEqual(found["Sample"], .type)
        XCTAssertEqual(found["\"Fira Code\""], .string)
        XCTAssertEqual(found["12.5"], .number)
    }

    func testKeywordsInsideOtherWordsStayPlain() {
        let tokens = CodeTokens.tokens(in: "letter = inside")
        XCTAssertEqual(tokens, [CodeTokens.Token(text: "letter = inside", kind: .plain)])
    }

    func testWordsInsideStringsAndCommentsKeepTheirColour() {
        let tokens = CodeTokens.tokens(in: "\"for 12 Fonts\" // let 3")
        XCTAssertEqual(tokens.map(\.kind), [.string, .plain, .comment])
    }

    func testAnUnfinishedStringEndsWithItsLine() {
        let tokens = CodeTokens.tokens(in: "\"open\nlet")
        XCTAssertEqual(tokens.map(\.text), ["\"open", "\n", "let"])
    }
}
