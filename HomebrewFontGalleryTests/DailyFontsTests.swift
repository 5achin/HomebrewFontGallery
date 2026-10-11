import XCTest
@testable import HomebrewFontGallery

final class DailyFontsTests: XCTestCase {
    private func font(_ token: String) -> WidgetFont {
        WidgetFont(token: token, name: token, url: URL(string: "https://example.com/\(token).ttf")!, sha256: nil)
    }

    private var catalogue: [WidgetFont] {
        (0..<60).map { font("font-text-\($0)") } + (0..<20).map { font("font-sample-mono-\($0)") }
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
        XCTAssertNotEqual(today.code, tomorrow.code)
    }

    func testPicksTheNumberAskedForWithoutRepeats() {
        let picked = DailyFonts.pick(from: catalogue, day: "2026-10-11", textCount: 16, codeCount: 8)
        XCTAssertEqual(picked.text.count, 16)
        XCTAssertEqual(picked.code.count, 8)
        XCTAssertEqual(Set(picked.text).count, 16)
        XCTAssertEqual(Set(picked.code).count, 8)
    }

    func testCodeFontsAreMonospacedAndTextFontsAreNot() {
        let picked = DailyFonts.pick(from: catalogue, day: "2026-10-11")
        XCTAssertTrue(picked.code.allSatisfy(\.isMonospaced))
        XCTAssertFalse(picked.text.contains(where: \.isMonospaced))
    }

    func testASmallCatalogueGivesWhatItHas() {
        let picked = DailyFonts.pick(from: [font("font-a"), font("font-b-mono")], day: "2026-10-11")
        XCTAssertEqual(picked.text.map(\.token), ["font-a"])
        XCTAssertEqual(picked.code.map(\.token), ["font-b-mono"])
    }

    func testMonospacedIsReadFromTheName() {
        XCTAssertTrue(font("font-fira-code").isMonospaced)
        XCTAssertTrue(font("font-jetbrains-mono").isMonospaced)
        XCTAssertTrue(font("font-courier-prime").isMonospaced)
        XCTAssertFalse(font("font-inter").isMonospaced)
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
