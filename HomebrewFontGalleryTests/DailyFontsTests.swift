import XCTest
@testable import HomebrewFontGallery

final class DailyFontsTests: XCTestCase {
    private func font(_ token: String, category: String? = nil) -> WidgetFont {
        WidgetFont(token: token, name: token, url: URL(string: "https://example.com/\(token).ttf")!, sha256: nil, category: category)
    }

    private var catalogue: [WidgetFont] {
        (0..<30).map { font("font-sans-\($0)", category: "Sans Serif") }
            + (0..<30).map { font("font-serif-\($0)", category: "Serif") }
            + (0..<40).map { font("font-display-\($0)", category: $0 % 2 == 0 ? "Display" : "Handwriting") }
            + (0..<20).map { font("font-fixed-\($0)", category: "Monospace") }
    }

    func testTheSameDayAlwaysPicksTheSameFonts() {
        let first = DailyFonts.pick(from: catalogue, day: "2026-10-11")
        let second = DailyFonts.pick(from: catalogue.reversed(), day: "2026-10-11")
        XCTAssertEqual(first, second)
    }

    func testAnotherDayPicksOtherFonts() {
        let today = DailyFonts.pick(from: catalogue, day: "2026-10-11")
        let tomorrow = DailyFonts.pick(from: catalogue, day: "2026-10-12")
        XCTAssertNotEqual(today.text, tomorrow.text)
        XCTAssertNotEqual(today.expressive, tomorrow.expressive)
        XCTAssertNotEqual(today.code, tomorrow.code)
    }

    func testPicksTheNumberAskedForWithoutRepeats() {
        let picked = DailyFonts.pick(from: catalogue, day: "2026-10-11", textCount: 14, expressiveCount: 8, codeCount: 12)
        XCTAssertEqual(Set(picked.text).count, 14)
        XCTAssertEqual(Set(picked.expressive).count, 8)
        XCTAssertEqual(Set(picked.code).count, 12)
    }

    func testEachKindOfFontIsPickedSeparately() {
        let picked = DailyFonts.pick(from: catalogue, day: "2026-10-11")
        XCTAssertTrue(picked.code.allSatisfy(\.isMonospaced))
        XCTAssertTrue(picked.text.allSatisfy { $0.kind != .expressive && !$0.isMonospaced })
        XCTAssertTrue(picked.expressive.allSatisfy { $0.kind == .expressive && !$0.isMonospaced })
    }

    func testASmallCatalogueGivesWhatItHas() {
        let picked = DailyFonts.pick(from: [font("font-a"), font("font-b-mono"), font("font-c", category: "Serif")], day: "2026-10-11")
        XCTAssertEqual(picked.expressive.map(\.token), ["font-a"])
        XCTAssertEqual(picked.code.map(\.token), ["font-b-mono"])
        XCTAssertEqual(picked.text.map(\.token), ["font-c"])
    }

    func testMonospacedIsReadFromTheNameWhenThereIsNoCategory() {
        XCTAssertTrue(font("font-fira-code").isMonospaced)
        XCTAssertTrue(font("font-jetbrains-mono").isMonospaced)
        XCTAssertTrue(font("font-courier-prime").isMonospaced)
        XCTAssertFalse(font("font-inter").isMonospaced)
        // "Monomaniac One" is a display font, whatever its name suggests.
        XCTAssertFalse(font("font-monomaniac-one", category: "Display").isMonospaced)
        XCTAssertTrue(font("font-cousine", category: "Monospace").isMonospaced)
    }

    func testKindComesFromTheCategoryOrFailingThatTheName() {
        func named(_ name: String, _ category: String? = nil) -> WidgetFont {
            WidgetFont(token: "font-x", name: name, url: URL(string: "https://example.com/x.ttf")!, sha256: nil, category: category)
        }
        XCTAssertEqual(named("Inter", "Sans Serif").kind, .sans)
        XCTAssertEqual(named("Lora", "Serif").kind, .serif)
        XCTAssertEqual(named("Lobster", "Display").kind, .expressive)
        XCTAssertEqual(named("Caveat", "Handwriting").kind, .expressive)
        XCTAssertEqual(named("42dot Sans").kind, .sans)
        XCTAssertEqual(named("Roboto Slab").kind, .serif)
        XCTAssertEqual(named("Mystery").kind, .expressive)
        XCTAssertEqual(named("Bona Nova SC", "Serif").kind, .expressive)
        XCTAssertEqual(named("Sankofa Display", "Sans Serif").kind, .expressive)
    }

    func testGoogleCategoriesAreReadByFamilyName() {
        let metadata = Data(#"{"familyMetadataList":[{"family":"ABeeZee","category":"Sans Serif","size":1},{"family":"Lora","category":"Serif"}]}"#.utf8)
        XCTAssertEqual(WidgetFontExport.categories(inGoogleMetadata: metadata), ["abeezee": "Sans Serif", "lora": "Serif"])
        XCTAssertEqual(WidgetFontExport.categories(inGoogleMetadata: Data("<html>".utf8)), [:])
    }

    func testDayIsWrittenInTheCalendarsTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        // 06:30 UTC on the 12th is still the evening of the 11th in Los Angeles.
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-12T06:30:00Z"))
        XCTAssertEqual(DailyFonts.day(for: date, calendar: calendar), "2026-10-11")
        let next = DailyFonts.nextDay(after: date, calendar: calendar)
        XCTAssertEqual(ISO8601DateFormatter().string(from: next), "2026-10-12T07:00:00Z")
    }

    func testPositionGoesRoundAtEitherEnd() {
        XCTAssertEqual(DailyFonts.position(0, count: 8), 0)
        XCTAssertEqual(DailyFonts.position(8, count: 8), 0)
        XCTAssertEqual(DailyFonts.position(-1, count: 8), 7)
        XCTAssertEqual(DailyFonts.position(-17, count: 8), 7)
        XCTAssertEqual(DailyFonts.position(3, count: 0), 0)
    }

    func testCatalogueSurvivesBeingWrittenAndRead() throws {
        let fonts = [
            WidgetFont(token: "font-b", name: "B", url: URL(string: "https://example.com/b%5Bwght%5D.ttf")!, sha256: String(repeating: "a", count: 64)),
            font("font-a"),
        ]
        let decoded = try WidgetFont.decodeCatalogue(WidgetFont.encodeCatalogue(fonts))
        XCTAssertEqual(decoded.map(\.token), ["font-a", "font-b"])
        XCTAssertEqual(Set(decoded), Set(fonts))
    }

    func testCatalogueKeepsOnlyFontsWhoseFileDownloadsByItself() {
        func cask(_ token: String, url: String, needsInstaller: Bool = false, isDisabled: Bool = false) -> FontCask {
            FontCask(token: token, name: token, alternateNames: [], summary: nil, homepage: nil, downloadURL: URL(string: url),
                     sha256: nil, version: "1", installedVersion: nil, fontFiles: [], sourceFiles: [], repositoryFolder: nil,
                     needsInstaller: needsInstaller, isDeprecated: false, isDisabled: isDisabled)
        }
        let fonts = WidgetFontExport.catalogue(from: [
            cask("font-single", url: "https://example.com/Single.ttf"),
            cask("font-zipped", url: "https://example.com/Zipped.zip"),
            cask("font-insecure", url: "http://example.com/Insecure.ttf"),
            cask("font-withdrawn", url: "https://example.com/Withdrawn.ttf", isDisabled: true),
            cask("font-noto-sans-sharada", url: "https://example.com/NotoSansSharada.ttf"),
            cask("font-noto-serif", url: "https://example.com/NotoSerif.ttf"),
            cask("font-libre-barcode-39-text", url: "https://example.com/LibreBarcode39Text.ttf"),
        ])
        XCTAssertEqual(fonts.map(\.token), ["font-single", "font-noto-serif"])
    }
}
