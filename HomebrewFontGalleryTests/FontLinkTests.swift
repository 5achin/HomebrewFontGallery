import XCTest
@testable import HomebrewFontGallery

final class FontLinkTests: XCTestCase {
    func testALinkNamesItsFont() throws {
        let url = try XCTUnwrap(FontLink.url(for: "font-fira-code"))
        XCTAssertEqual(url.absoluteString, "homebrewfontgallery://font/font-fira-code")
        XCTAssertEqual(FontLink.token(from: url), "font-fira-code")
    }

    func testOtherLinksAreIgnored() throws {
        for link in ["https://font/font-fira-code", "homebrewfontgallery://other/font-fira-code",
                     "homebrewfontgallery://font/", "homebrewfontgallery://font/fira-code",
                     "homebrewfontgallery://font/font-a/font-b"] {
            XCTAssertNil(FontLink.token(from: try XCTUnwrap(URL(string: link))), link)
        }
    }
}
