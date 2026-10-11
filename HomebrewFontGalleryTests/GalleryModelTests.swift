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

    func testOneSelectedFontIsInstalledOrUninstalled() {
        let install = GalleryModel.action(for: [fonts[1]])
        XCTAssertEqual(install?.kind, .install)
        XCTAssertEqual(install?.title, "Install")
        XCTAssertEqual(install?.fonts.map(\.name), ["Inter"])
        let uninstall = GalleryModel.action(for: [fonts[0]])
        XCTAssertEqual(uninstall?.kind, .uninstall)
        XCTAssertEqual(uninstall?.title, "Uninstall")
        XCTAssertNil(GalleryModel.action(for: []))
    }

    func testSeveralSelectedFontsInstallTheOnesNotYetInstalled() {
        let mixed = GalleryModel.action(for: fonts)
        XCTAssertEqual(mixed?.kind, .install)
        XCTAssertEqual(mixed?.fonts.map(\.name), ["Inter", "San Francisco Pro"])
        XCTAssertEqual(mixed?.title, "Install 2 Fonts")
        XCTAssertEqual(GalleryModel.action(for: [fonts[0], fonts[1]])?.title, "Install 1 Font")
    }

    func testSeveralInstalledFontsAreUninstalledTogether() {
        let installed = [font("font-a", name: "A", installed: true), font("font-b", name: "B", installed: true)]
        let action = GalleryModel.action(for: installed)
        XCTAssertEqual(action?.kind, .uninstall)
        XCTAssertEqual(action?.title, "Uninstall 2 Fonts")
        XCTAssertEqual(action?.fonts, installed)
    }

    func testBatchStatusCountsWhatFinished() {
        let done = GalleryModel.batchStatus(kind: .installing, batch: fonts, finished: fonts, failed: [], wasCancelled: false)
        XCTAssertEqual(done.kind, .success)
        XCTAssertEqual(done.title, "Installed 3 Fonts")
        XCTAssertEqual(done.tokens, ["font-fira-code", "font-inter", "font-sf-pro"])

        let partial = GalleryModel.batchStatus(kind: .installing, batch: fonts, finished: [fonts[0], fonts[2]],
                                               failed: [fonts[1]], wasCancelled: false)
        XCTAssertEqual(partial.kind, .failure)
        XCTAssertEqual(partial.title, "Couldn’t Install 1 Font")
        XCTAssertTrue(partial.message.hasPrefix("Installed 2 of 3 fonts. Homebrew reported a problem with “Inter”."))

        let stopped = GalleryModel.batchStatus(kind: .uninstalling, batch: fonts, finished: [fonts[0]], failed: [],
                                               wasCancelled: true)
        XCTAssertEqual(stopped.kind, .cancelled)
        XCTAssertEqual(stopped.title, "Uninstall Stopped")
        XCTAssertEqual(stopped.message, "Uninstalled 1 of 3 fonts before stopping.")
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

    func testCategoryCountsAndFiltersByTheLastWordOfTheName() {
        let categories = FontCategory.top(2, in: fonts)
        let mono = categories.first
        XCTAssertEqual(mono?.count, 3)
        XCTAssertEqual(GalleryModel.filter(fonts, by: .all, searchText: "", category: mono).map(\.name),
                       ["Fira Mono", "Agave Nerd Font (Agave MONO)", "Roboto Mono"])
        // "Noto Sans JP" and "Noto Sans 2" have the word, but don't end in it.
        let sans = categories.last
        XCTAssertEqual(sans?.count, 2)
        XCTAssertEqual(GalleryModel.filter(fonts, by: .all, searchText: "", category: sans).map(\.name),
                       ["Fira Sans", "Open Sans"])
        XCTAssertEqual(GalleryModel.filter(fonts, by: .all, searchText: "open", category: sans).map(\.name), ["Open Sans"])
    }

    func testLimitAndEmptyInput() {
        XCTAssertEqual(FontCategory.top(1, in: fonts).count, 1)
        XCTAssertEqual(FontCategory.top(5, in: []), [])
    }
}
