import XCTest
@testable import HomebrewFontGallery

final class GalleryModelTests: XCTestCase {
    private func font(_ token: String, name: String, installed: Bool = false, alternateNames: [String] = []) -> FontCask {
        FontCask(token: token, name: name, alternateNames: alternateNames, summary: nil, homepage: nil, downloadURL: nil,
                 sha256: nil, version: "1.0", installedVersion: installed ? "1.0" : nil, fontFiles: [],
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
