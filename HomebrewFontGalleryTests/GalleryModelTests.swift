import XCTest
@testable import HomebrewFontGallery

final class GalleryModelTests: XCTestCase {
    private func font(_ token: String, name: String, installed: Bool = false, alternateNames: [String] = []) -> FontCask {
        FontCask(token: token, name: name, alternateNames: alternateNames, summary: nil, homepage: nil, downloadURL: nil,
                 sha256: nil, version: "1.0", installedVersion: installed ? "1.0" : nil, fontFiles: [], sourceFiles: [], repositoryFolder: nil,
                 needsInstaller: false, isDeprecated: false, isDisabled: false)
    }

    private var fonts: [FontCask] {
        [
            font("font-fira-code", name: "Fira Code", installed: true),
            font("font-inter", name: "Inter"),
            font("font-sf-pro", name: "San Francisco Pro", alternateNames: ["SF Pro"]),
        ]
    }

    func testFilters() {
        XCTAssertEqual(GalleryModel.filter(fonts, by: .all, searchText: "").count, 3)
        XCTAssertEqual(GalleryModel.filter(fonts, by: .installed, searchText: "").map(\.name), ["Fira Code"])
        XCTAssertEqual(GalleryModel.filter(fonts, by: .notInstalled, searchText: "").map(\.name), ["Inter", "San Francisco Pro"])
    }

    func testSearchMatchesNameAlternateNameAndToken() {
        XCTAssertEqual(GalleryModel.filter(fonts, by: .all, searchText: " fira ").map(\.name), ["Fira Code"])
        XCTAssertEqual(GalleryModel.filter(fonts, by: .all, searchText: "sf pro").map(\.name), ["San Francisco Pro"])
        XCTAssertEqual(GalleryModel.filter(fonts, by: .all, searchText: "font-inter").map(\.name), ["Inter"])
        XCTAssertEqual(GalleryModel.filter(fonts, by: .installed, searchText: "inter"), [])
    }

    func testMissingBrewIsReportedWithoutRunningAnything() async {
        let service = BrewService(executable: nil)
        do {
            _ = try await service.allFonts()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? BrewError, .notInstalled)
        }
    }
}

final class FontCategoryTests: XCTestCase {
    private func font(_ name: String) -> FontCask {
        FontCask(token: "font-" + name.lowercased().filter { $0.isLetter || $0.isNumber }, name: name, alternateNames: [],
                 summary: nil, homepage: nil, downloadURL: nil, sha256: nil, version: "1.0", installedVersion: nil,
                 fontFiles: [], sourceFiles: [], repositoryFolder: nil, needsInstaller: false, isDeprecated: false, isDisabled: false)
    }

    private var fonts: [FontCask] {
        ["Fira Sans", "Open Sans", "Noto Sans JP", "Fira Mono", "Agave Nerd Font (Agave MONO)", "Roboto Mono",
         "Inter", "Noto Sans 2", "Plex X"].map(font)
    }

    func testWordsDropPunctuation() {
        XCTAssertEqual(FontCategory.words(in: "Literation Nerd Font (Liberation Mono)"),
                       ["Literation", "Nerd", "Font", "Liberation", "Mono"])
    }

    func testTopCategoriesAreTheMostCommonLastWords() {
        let categories = FontCategory.top(2, in: fonts)
        // "Mono" ends three names and "Sans" two; numbers and single letters aren't counted as endings.
        XCTAssertEqual(categories.map(\.word), ["Mono", "Sans"])
    }

    func testCategoryCountsAndFiltersByTheWordAnywhereInTheName() {
        let sans = try? XCTUnwrap(FontCategory.top(2, in: fonts).last)
        XCTAssertEqual(sans?.count, 4)
        XCTAssertEqual(GalleryModel.filter(fonts, by: .all, searchText: "", category: sans).map(\.name),
                       ["Fira Sans", "Open Sans", "Noto Sans JP", "Noto Sans 2"])
        XCTAssertEqual(GalleryModel.filter(fonts, by: .all, searchText: "noto", category: sans).map(\.name),
                       ["Noto Sans JP", "Noto Sans 2"])
    }

    func testLimitAndEmptyInput() {
        XCTAssertEqual(FontCategory.top(1, in: fonts).count, 1)
        XCTAssertEqual(FontCategory.top(5, in: []), [])
    }
}
