import XCTest
@testable import HomebrewFontGallery

final class BrewParsingTests: XCTestCase {
    /// Captured from `brew info --json=v2 --cask` with Homebrew 7.0.9.
    private func fixtureFonts() throws -> [String: FontCask] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "brew-info", withExtension: "json"))
        let fonts = try BrewParsing.fonts(fromInfoJSON: Data(contentsOf: url))
        return Dictionary(uniqueKeysWithValues: fonts.map { ($0.token, $0) })
    }

    // MARK: brew casks

    func testFontTokensKeepsOnlyFontsSortedAndUnique() {
        let output = """
        firefox
        font-inter
        font-fira-code
        fontforge-app
        font-inter

        visual-studio-code
        """
        XCTAssertEqual(BrewParsing.fontTokens(fromCaskList: output), ["font-fira-code", "font-inter"])
    }

    func testFontTokensIgnoresWarningsAndOddLines() {
        let output = "Warning: something\n  font-abel  \nfont-\nfont-Bad Name\nfont-m+\nfont-sf-pro@beta\n"
        XCTAssertEqual(BrewParsing.fontTokens(fromCaskList: output), ["font-abel", "font-m+", "font-sf-pro@beta"])
    }

    func testFontTokensFromEmptyOutput() {
        XCTAssertEqual(BrewParsing.fontTokens(fromCaskList: ""), [])
    }

    func testTokensThatCouldBeOptionsAreRejected() {
        XCTAssertFalse(BrewParsing.isFontToken("--force"))
        XCTAssertFalse(BrewParsing.isFontToken("font-a b"))
        XCTAssertFalse(BrewParsing.isFontToken("font-a;rm"))
        XCTAssertFalse(BrewParsing.isFontToken("firefox"))
        XCTAssertTrue(BrewParsing.isFontToken("font-3270-nerd-font"))
    }

    // MARK: Arguments

    func testArguments() {
        XCTAssertEqual(BrewParsing.listAllArguments, ["casks"])
        XCTAssertEqual(BrewParsing.infoArguments(tokens: ["font-abel", "font-inter"]),
                       ["info", "--json=v2", "--cask", "font-abel", "font-inter"])
        XCTAssertEqual(BrewParsing.installArguments(token: "font-abel"), ["install", "--cask", "font-abel"])
        XCTAssertEqual(BrewParsing.uninstallArguments(token: "font-abel"), ["uninstall", "--cask", "font-abel"])
    }

    // MARK: brew info

    func testInfoDecodesEveryFontInTheFixture() throws {
        XCTAssertEqual(try fixtureFonts().count, 8)
    }

    func testFontThatIsNotInstalled() throws {
        let font = try XCTUnwrap(fixtureFonts()["font-fira-code"])
        XCTAssertEqual(font.name, "Fira Code")
        XCTAssertEqual(font.alternateNames, [])
        XCTAssertNil(font.summary)
        XCTAssertEqual(font.version, "6.2")
        XCTAssertNil(font.installedVersion)
        XCTAssertFalse(font.isInstalled)
        XCTAssertTrue(font.isInstallable)
        XCTAssertEqual(font.homepage, URL(string: "https://github.com/tonsky/FiraCode"))
        XCTAssertEqual(font.sha256, "0949915ba8eb24d89fd93d10a7ff623f42830d7c5ffc3ecbf960e4ecad3e3e79")
        XCTAssertEqual(font.fontFiles.count, 7)
        XCTAssertEqual(font.fontFiles.first?.path, "/Users/me/Library/Fonts/FiraCode-Bold.ttf")
        // A zip can't be previewed before it is installed.
        XCTAssertNil(font.previewDownloadURL)
    }

    func testInstalledFont() throws {
        let font = try XCTUnwrap(fixtureFonts()["font-maple-mono"])
        XCTAssertEqual(font.name, "Maple Mono")
        XCTAssertEqual(font.installedVersion, "7.9")
        XCTAssertTrue(font.isInstalled)
    }

    func testInstalledFontWithoutVersionNumber() throws {
        let font = try XCTUnwrap(fixtureFonts()["font-spline-sans-mono"])
        XCTAssertEqual(font.installedVersion, "latest")
        XCTAssertTrue(font.isInstalled)
        XCTAssertNil(font.sha256, "no_check is not a checksum")
    }

    func testSingleFontFileCanBePreviewedBeforeInstalling() throws {
        let font = try XCTUnwrap(fixtureFonts()["font-abel"])
        XCTAssertEqual(font.previewDownloadURL,
                       URL(string: "https://github.com/google/fonts/raw/main/ofl/abel/Abel-Regular.ttf"))
        XCTAssertNil(font.sha256)
        XCTAssertEqual(font.fontFiles.map(\.lastPathComponent), ["Abel-Regular.ttf"])
    }

    func testFontWithInstallerPackageIsNotInstallable() throws {
        let font = try XCTUnwrap(fixtureFonts()["font-sf-pro"])
        XCTAssertEqual(font.name, "San Francisco Pro")
        XCTAssertEqual(font.alternateNames, ["SF Pro"])
        XCTAssertTrue(font.needsInstaller)
        XCTAssertFalse(font.isInstallable)
        XCTAssertEqual(font.fontFiles, [])
    }

    func testDisabledAndDeprecatedFonts() throws {
        let fonts = try fixtureFonts()
        let disabled = try XCTUnwrap(fonts["font-andagii"])
        XCTAssertTrue(disabled.isDisabled)
        XCTAssertFalse(disabled.isInstallable)

        let deprecated = try XCTUnwrap(fonts["font-ark-pixel-16px-monospaced"])
        XCTAssertTrue(deprecated.isDeprecated)
        XCTAssertFalse(deprecated.isDisabled)
        XCTAssertTrue(deprecated.isInstallable)
    }

    func testAlternateNames() throws {
        let font = try XCTUnwrap(fixtureFonts()["font-chenyuluoyan"])
        XCTAssertEqual(font.name, "Chenyuluoyan")
        XCTAssertEqual(font.alternateNames, ["辰宇落雁體"])
    }

    func testInfoToleratesMissingFieldsAndSkipsOtherCasks() throws {
        let json = """
        {"formulae": [], "casks": [
          {"token": "font-bare-minimum"},
          {"token": "firefox", "name": ["Firefox"]},
          {"token": "font-odd", "name": [""], "desc": "", "installed": "", "sha256": "no_check",
           "url": "http://example.com/Odd.ttf",
           "artifacts": [{"font": ["Odd.ttf"], "target": "/Users/me/Library/Fonts/Odd.ttf"},
                         {"uninstall": [{"pkgutil": "x"}]}, ["unexpected"], "string", {"artifact": ["a"], "target": "/tmp/a"}]}
        ]}
        """
        let fonts = try BrewParsing.fonts(fromInfoJSON: Data(json.utf8))
        XCTAssertEqual(fonts.map(\.token), ["font-bare-minimum", "font-odd"])
        XCTAssertEqual(fonts[0].name, "Bare Minimum")
        XCTAssertEqual(fonts[0].version, "")
        XCTAssertFalse(fonts[0].isInstalled)
        XCTAssertEqual(fonts[1].name, "Odd")
        XCTAssertNil(fonts[1].summary)
        XCTAssertFalse(fonts[1].isInstalled)
        XCTAssertEqual(fonts[1].fontFiles.map(\.path), ["/Users/me/Library/Fonts/Odd.ttf"])
        XCTAssertNil(fonts[1].previewDownloadURL, "Previews are only downloaded over HTTPS")
    }

    func testInfoRejectsOutputThatIsNotJSON() {
        XCTAssertThrowsError(try BrewParsing.fonts(fromInfoJSON: Data("Error: Cask 'font-x' is unavailable".utf8)))
        XCTAssertThrowsError(try BrewParsing.fonts(fromInfoJSON: Data()))
    }

    func testDisplayNameFromToken() {
        XCTAssertEqual(BrewParsing.displayName(fromToken: "font-fira-code"), "Fira Code")
        XCTAssertEqual(BrewParsing.displayName(fromToken: "font-3270"), "3270")
    }
}
