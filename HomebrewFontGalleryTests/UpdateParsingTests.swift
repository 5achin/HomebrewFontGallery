import XCTest
@testable import HomebrewFontGallery

final class UpdateParsingTests: XCTestCase {
    /// Captured from GitHub's `releases/latest` for this app, with the fields the app doesn't read trimmed.
    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "github-release", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    /// The fixture with some of its text swapped, to stand for a release that is slightly different.
    private func fixture(replacing old: String, with new: String) throws -> Data {
        let text = String(decoding: try fixture(), as: UTF8.self)
        XCTAssertTrue(text.contains(old), "The fixture doesn't contain \(old)")
        return Data(text.replacingOccurrences(of: old, with: new).utf8)
    }

    // MARK: Tags

    func testVersionFromBuildTag() {
        let parsed = UpdateParsing.version(fromTag: "v1.0-build.37")
        XCTAssertEqual(parsed?.version, "1.0")
        XCTAssertEqual(parsed?.build, 37)
        XCTAssertEqual(UpdateParsing.version(fromTag: "v2.10.3-build.1204")?.version, "2.10.3")
        XCTAssertEqual(UpdateParsing.version(fromTag: "v2.10.3-build.1204")?.build, 1204)
    }

    func testOtherTagsHaveNoBuild() {
        for tag in ["v1.0", "1.0-build.37", "v1.0-build.", "v1.0-build.x", "v1.0-build.37-beta", "v-build.3", "v1.0-build.-3", ""] {
            XCTAssertNil(UpdateParsing.version(fromTag: tag), tag)
        }
    }

    // MARK: Releases

    func testUpdateFromCapturedRelease() throws {
        let update = try XCTUnwrap(UpdateParsing.update(fromReleaseJSON: fixture()))
        XCTAssertEqual(update.version, "1.0")
        XCTAssertEqual(update.build, 36)
        XCTAssertEqual(update.downloadURL.absoluteString,
                       "https://github.com/5achin/HomebrewFontGallery/releases/download/v1.0-build.36/HomebrewFontGallery-v1.0-build.36.zip")
        XCTAssertEqual(update.sha256, "7893f53845807dbbb1fdd6ed9d64e2b32dbe62adfbe8aec7dbacdb707f367fe1")
        XCTAssertEqual(update.size, 9_425_165)
    }

    func testDraftsAndPrereleasesAreNotOffered() throws {
        XCTAssertNil(try UpdateParsing.update(fromReleaseJSON: fixture(replacing: "\"draft\": false", with: "\"draft\": true")))
        XCTAssertNil(try UpdateParsing.update(fromReleaseJSON: fixture(replacing: "\"prerelease\": false", with: "\"prerelease\": true")))
    }

    func testReleaseWithoutChecksumIsNotOffered() throws {
        XCTAssertNil(try UpdateParsing.update(fromReleaseJSON: fixture(replacing: "\"sha256:7893", with: "\"md5:7893")))
        XCTAssertNil(try UpdateParsing.update(fromReleaseJSON: fixture(replacing: "\"digest\": \"sha256:7893f53845807dbbb1fdd6ed9d64e2b32dbe62adfbe8aec7dbacdb707f367fe1\"", with: "\"digest\": null")))
    }

    func testReleaseWithoutTheAppZipIsNotOffered() throws {
        XCTAssertNil(try UpdateParsing.update(fromReleaseJSON: fixture(replacing: "\"name\": \"HomebrewFontGallery-v1.0-build.36.zip\"", with: "\"name\": \"Source.zip\"")))
        XCTAssertNil(try UpdateParsing.update(fromReleaseJSON: fixture(replacing: "\"tag_name\": \"v1.0-build.36\"", with: "\"tag_name\": \"v1.0\"")))
    }

    func testDownloadFromAnotherPlaceIsNotOffered() throws {
        XCTAssertNil(try UpdateParsing.update(fromReleaseJSON: fixture(replacing: "https://github.com/5achin/HomebrewFontGallery/releases/download/", with: "https://example.com/5achin/HomebrewFontGallery/releases/download/")))
        XCTAssertNil(try UpdateParsing.update(fromReleaseJSON: fixture(replacing: "https://github.com/5achin/HomebrewFontGallery/releases/download/", with: "http://github.com/5achin/HomebrewFontGallery/releases/download/")))
        XCTAssertNil(try UpdateParsing.update(fromReleaseJSON: fixture(replacing: "https://github.com/5achin/HomebrewFontGallery/releases/download/", with: "https://github.com/someone/else/releases/download/")))
    }

    func testOtherJSONThrows() {
        XCTAssertThrowsError(try UpdateParsing.update(fromReleaseJSON: Data(#"{"message": "Not Found"}"#.utf8)))
        XCTAssertThrowsError(try UpdateParsing.update(fromReleaseJSON: Data("<html>".utf8)))
    }

    // MARK: Pieces

    func testReleaseDownloadLinks() throws {
        func allowed(_ string: String) throws -> Bool {
            UpdateParsing.isReleaseDownload(try XCTUnwrap(URL(string: string)))
        }
        XCTAssertTrue(try allowed("https://github.com/5achin/HomebrewFontGallery/releases/download/v1.0-build.2/a.zip"))
        XCTAssertFalse(try allowed("https://github.com.example.com/5achin/HomebrewFontGallery/releases/download/v1/a.zip"))
        XCTAssertFalse(try allowed("https://user@github.com/5achin/HomebrewFontGallery/releases/download/v1/a.zip"))
        XCTAssertFalse(try allowed("https://github.com:8443/5achin/HomebrewFontGallery/releases/download/v1/a.zip"))
        XCTAssertFalse(try allowed("https://github.com/5achin/HomebrewFontGallery/archive/main.zip"))
    }

    func testDigest() {
        let hex = String(repeating: "aB", count: 32)
        XCTAssertEqual(UpdateParsing.sha256(fromDigest: "sha256:\(hex)"), hex.lowercased())
        XCTAssertNil(UpdateParsing.sha256(fromDigest: nil))
        XCTAssertNil(UpdateParsing.sha256(fromDigest: hex))
        XCTAssertNil(UpdateParsing.sha256(fromDigest: "sha256:\(hex.dropLast())"))
        XCTAssertNil(UpdateParsing.sha256(fromDigest: "sha512:\(hex)"))
    }

    func testBuildFromBundleVersion() {
        XCTAssertEqual(UpdateParsing.build(fromBundleVersion: "37"), 37)
        XCTAssertNil(UpdateParsing.build(fromBundleVersion: "1.2"))
        XCTAssertNil(UpdateParsing.build(fromBundleVersion: nil))
        XCTAssertNil(UpdateParsing.build(fromBundleVersion: 37))
    }

    // MARK: Checking a download

    func testSHA256OfFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("UpdateParsingTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)
        XCTAssertEqual(try UpdateService.sha256(ofFileAt: file), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testAppInADifferentPlaceOrBuildIsRejected() throws {
        // The app the tests run inside is a real, signed copy of the app, at the local build.
        let app = Bundle.main.bundleURL
        let service = UpdateService()
        let build = try XCTUnwrap(UpdateParsing.build(fromBundleVersion: Bundle.main.infoDictionary?["CFBundleVersion"]))
        func update(build: Int) throws -> AppUpdate {
            AppUpdate(version: "1.0", build: build, downloadURL: try XCTUnwrap(URL(string: "https://github.com")), sha256: "", size: 0)
        }
        XCTAssertNoThrow(try service.verify(app, is: update(build: build)))
        XCTAssertThrowsError(try service.verify(app, is: update(build: build + 1))) {
            XCTAssertEqual($0 as? UpdateError, .notTheExpectedApp)
        }
        var other = UpdateService()
        other.bundleIdentifier = "com.example.Other"
        XCTAssertThrowsError(try other.verify(app, is: update(build: build))) {
            XCTAssertEqual($0 as? UpdateError, .notTheExpectedApp)
        }
        XCTAssertThrowsError(try service.verify(app.appendingPathComponent("Missing.app"), is: update(build: build))) {
            XCTAssertEqual($0 as? UpdateError, .notTheExpectedApp)
        }
    }

    // MARK: Messages

    func testEveryFailureHasATitleAndAMessage() {
        let errors: [UpdateError] = [.network, .unreadableRelease, .downloadFailed, .checksumMismatch, .unpackFailed,
                                     .notTheExpectedApp, .translocated, .folderNotWritable, .replaceFailed]
        for error in errors {
            guard case .failed(let title, let message) = UpdateModel.failure(for: error) else {
                return XCTFail("\(error) has no message")
            }
            XCTAssertFalse(title.isEmpty)
            XCTAssertTrue(message.hasSuffix("."), message)
        }
    }
}
