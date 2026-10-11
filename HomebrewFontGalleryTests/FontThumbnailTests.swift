import XCTest
@testable import HomebrewFontGallery

final class FontThumbnailTests: XCTestCase {
    /// A font every Mac has, standing in for one Homebrew would install.
    private func systemFace() throws -> FontFace {
        let file = URL(fileURLWithPath: "/System/Library/Fonts/Helvetica.ttc")
        return try XCTUnwrap(FontPreview.faces(in: [file]).first)
    }

    func testFacesPutRegularFirst() throws {
        XCTAssertEqual(try systemFace().name, "Regular")
    }

    func testThumbnailIsAPictureOfTheExpectedSizeWithSomethingDrawn() throws {
        let data = try XCTUnwrap(FontThumbnailRenderer.png(for: systemFace()))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(bitmap.pixelsWide, Int(FontThumbnailRenderer.size.width * FontThumbnailRenderer.scale))
        XCTAssertEqual(bitmap.pixelsHigh, Int(FontThumbnailRenderer.size.height * FontThumbnailRenderer.scale))

        // The corners are clear and the middle of the sample has ink.
        XCTAssertEqual(bitmap.colorAt(x: 0, y: 0)?.alphaComponent, 0)
        var inked = 0
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                inked += 1
            }
        }
        XCTAssertGreaterThan(inked, 100)
    }

    func testSavedThumbnailIsReadBackAsATemplateInPoints() throws {
        let data = try XCTUnwrap(FontThumbnailRenderer.png(for: systemFace()))
        let image = try XCTUnwrap(FontThumbnailRenderer.image(fromPNG: data))
        XCTAssertEqual(image.size, FontThumbnailRenderer.size)
        XCTAssertTrue(image.isTemplate)
        XCTAssertNil(FontThumbnailRenderer.image(fromPNG: Data("not a picture".utf8)))
    }
}
