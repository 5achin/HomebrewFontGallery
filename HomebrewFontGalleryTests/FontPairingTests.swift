import XCTest
@testable import HomebrewFontGallery

final class FontPairingTests: XCTestCase {
    private func font(_ name: String, _ kind: FontKind, xHeight: Double = 0.7, width: Double = 0.5,
                      weight: Double = 0) -> FontPairing.Candidate {
        FontPairing.Candidate(token: "font-" + name.lowercased().replacingOccurrences(of: " ", with: "-"), name: name,
                              traits: FontTraits(kind: kind, xHeight: xHeight, width: width, weight: weight))
    }

    func testOnlyPlainFontsOfOrdinaryProportionsSuitParagraphs() {
        XCTAssertTrue(FontPairing.suitsParagraphs(font("Plain", .sans).traits))
        XCTAssertTrue(FontPairing.suitsParagraphs(font("Bookish", .serif, xHeight: 0.62).traits))
        XCTAssertFalse(FontPairing.suitsParagraphs(font("Swirly", .expressive).traits))
        XCTAssertFalse(FontPairing.suitsParagraphs(font("Heavy", .sans, weight: 0.6).traits))
        XCTAssertFalse(FontPairing.suitsParagraphs(font("Hairline", .sans, weight: -0.6).traits))
        XCTAssertFalse(FontPairing.suitsParagraphs(font("Squeezed", .sans, width: 0.3).traits))
        XCTAssertFalse(FontPairing.suitsParagraphs(font("Small Caps", .serif, xHeight: 0.95).traits))
    }

    func testAFontIsNeverPairedWithItselfOrOverAnUnsuitableParagraph() {
        let sans = font("Plain", .sans)
        XCTAssertEqual(FontPairing.score(heading: sans, paragraph: sans), 0)
        XCTAssertEqual(FontPairing.score(heading: sans, paragraph: font("Swirly", .expressive)), 0)
    }

    func testContrastBeatsNearLikeness() {
        let paragraph = font("Plain", .sans)
        let serif = FontPairing.score(heading: font("Bookish", .serif), paragraph: paragraph)
        let display = FontPairing.score(heading: font("Swirly", .expressive), paragraph: paragraph)
        let heavierSans = FontPairing.score(heading: font("Other", .sans, weight: 0.4), paragraph: paragraph)
        let similarSans = FontPairing.score(heading: font("Other", .sans), paragraph: paragraph)
        XCTAssertGreaterThan(serif, display)
        XCTAssertGreaterThan(display, heavierSans)
        XCTAssertGreaterThan(heavierSans, similarSans)
    }

    func testSharedProportionsBeatMismatchedOnes() {
        let paragraph = font("Plain", .sans, xHeight: 0.72, width: 0.5)
        let matched = FontPairing.score(heading: font("Matched", .serif, xHeight: 0.71, width: 0.51), paragraph: paragraph)
        let short = FontPairing.score(heading: font("Short", .serif, xHeight: 0.6, width: 0.51), paragraph: paragraph)
        let narrow = FontPairing.score(heading: font("Narrow", .serif, xHeight: 0.71, width: 0.38), paragraph: paragraph)
        XCTAssertGreaterThan(matched, short)
        XCTAssertGreaterThan(matched, narrow)
    }

    func testOneFamilyIsTheBestMatch() {
        XCTAssertEqual(FontPairing.family(of: "Noto Serif Display"), "noto")
        XCTAssertEqual(FontPairing.family(of: "IBM Plex Sans Condensed"), "ibm plex")
        XCTAssertEqual(FontPairing.family(of: "Lora"), "lora")
        XCTAssertEqual(FontPairing.family(of: "Sans Forgetica"), "sans")
        let score = FontPairing.score(heading: font("Source Serif", .serif, xHeight: 0.62), paragraph: font("Source Sans", .sans, xHeight: 0.75))
        XCTAssertEqual(score, 1)
    }

    func testCombinationsAreBestFirstWithVariety() {
        let text = [
            font("Sans A", .sans, xHeight: 0.72), font("Grot B", .sans, xHeight: 0.66),
            font("Serif C", .serif, xHeight: 0.71), font("Roman D", .serif, xHeight: 0.64),
            font("Swirly", .expressive, xHeight: 0.5), font("Poster", .expressive, xHeight: 0.9, weight: 0.6),
        ]
        let code = [font("Fixed Tall", .sans, xHeight: 0.74), font("Fixed Short", .sans, xHeight: 0.63)]
        let combinations = FontPairing.combinations(text: text, code: code, limit: 8)

        XCTAssertEqual(combinations.count, 6)
        XCTAssertEqual(Set(combinations.map(\.heading)).count, 6, "Each font heads one combination.")
        XCTAssertTrue(combinations.allSatisfy { $0.heading != $0.paragraph })
        let paragraphs = Dictionary(grouping: combinations, by: \.paragraph)
        XCTAssertTrue(paragraphs.values.allSatisfy { $0.count <= 2 })
        XCTAssertFalse(paragraphs.keys.contains("font-swirly"))
        XCTAssertFalse(paragraphs.keys.contains("font-poster"))

        // The best pair is a serif over a sans of nearly the same proportions, or the reverse.
        XCTAssertEqual(Set([combinations[0].heading, combinations[0].paragraph]), ["font-sans-a", "font-serif-c"])
        // The first combination's code follows its paragraph's lowercase height, and after
        // that the code fonts take turns.
        XCTAssertEqual(combinations[0].code, "font-fixed-tall")
        XCTAssertEqual(combinations[1].code, "font-fixed-short")
        XCTAssertEqual(combinations.filter { $0.code == "font-fixed-tall" }.count, 3)
        for combination in combinations.prefix(4) {
            XCTAssertFalse(combinations.prefix(4).contains { $0.heading == combination.paragraph && $0.paragraph == combination.heading })
        }
        XCTAssertEqual(combinations, FontPairing.combinations(text: text.reversed(), code: code.reversed(), limit: 8))
        XCTAssertEqual(FontPairing.combinations(text: text, code: code, limit: 2).count, 2)
    }

    func testOneParagraphFontCarriesEveryCombinationWhenItIsTheOnlyOne() {
        let text = [font("Sans A", .sans), font("Swirly", .expressive), font("Poster", .expressive), font("Loopy", .expressive)]
        let combinations = FontPairing.combinations(text: text, code: [], limit: 8)
        XCTAssertEqual(Set(combinations.map(\.heading)), ["font-swirly", "font-poster", "font-loopy"])
        XCTAssertEqual(Set(combinations.map(\.paragraph)), ["font-sans-a"])
    }

    func testEveryCodeFontIsShownBeforeAnyRepeats() {
        let text = [
            font("Sans A", .sans), font("Grot B", .sans), font("Serif C", .serif), font("Roman D", .serif),
            font("Swirly", .expressive), font("Poster", .expressive),
        ]
        // All four suit the paragraphs about equally: without turns, one would take them all.
        let code = [font("Fixed One", .sans, xHeight: 0.70), font("Fixed Two", .sans, xHeight: 0.71),
                    font("Fixed Three", .sans, xHeight: 0.72), font("Fixed Four", .sans, xHeight: 0.73)]
        let combinations = FontPairing.combinations(text: text, code: code, limit: 8)
        XCTAssertEqual(Set(combinations.prefix(4).compactMap(\.code)).count, 4)
        XCTAssertEqual(Set(combinations.compactMap(\.code)).count, 4)
    }

    func testTheNearestCodeFontIsChosenAmongTheLeastUsed() {
        let paragraph = font("Sans A", .sans, xHeight: 0.72)
        let code = [font("Fixed Tall", .sans, xHeight: 0.73), font("Fixed Short", .sans, xHeight: 0.6)]
        XCTAssertEqual(FontPairing.codeFont(for: paragraph, from: code)?.token, "font-fixed-tall")
        XCTAssertEqual(FontPairing.codeFont(for: paragraph, from: code, uses: ["font-fixed-tall": 1])?.token, "font-fixed-short")
        XCTAssertNil(FontPairing.codeFont(for: paragraph, from: []))
    }

    func testNoPlainFontsMeansNoCombinations() {
        let text = [font("Swirly", .expressive), font("Poster", .expressive)]
        XCTAssertEqual(FontPairing.combinations(text: text, code: [], limit: 8), [])
    }

    func testCombinationsWithoutCodeFontsLeaveCodeEmpty() {
        let text = [font("Sans A", .sans), font("Serif C", .serif)]
        XCTAssertEqual(FontPairing.combinations(text: text, code: [], limit: 8).map(\.code), [nil, nil])
    }
}
