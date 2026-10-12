import XCTest
@testable import HomebrewFontGallery

final class WidgetRestartTests: XCTestCase {
    func testAProcessFromBeforeTheInstallIsStale() {
        let installed = Date(timeIntervalSince1970: 1_000_000)
        let before = WidgetRestart.Process(id: 1, started: installed.addingTimeInterval(-60))
        let after = WidgetRestart.Process(id: 2, started: installed.addingTimeInterval(60))
        XCTAssertTrue(WidgetRestart.isStale(before, installed: installed))
        XCTAssertFalse(WidgetRestart.isStale(after, installed: installed))
    }

    func testFindsARunningProcessByTheFileItWasStartedFrom() throws {
        // The app the tests run inside stands in for the widget.
        let executable = try XCTUnwrap(Bundle.main.executableURL)
        let found = WidgetRestart.processes(running: executable)
        let own = try XCTUnwrap(found.first { $0.id == getpid() })
        XCTAssertLessThan(own.started, Date())
        XCTAssertGreaterThan(own.started, Date().addingTimeInterval(-3600))
        XCTAssertEqual(WidgetRestart.processes(running: URL(fileURLWithPath: "/nowhere/at/all")), [])
    }

    func testAFileHasAnInstallDateAndAMissingOneHasNone() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let date = try XCTUnwrap(WidgetRestart.installDate(of: file))
        XCTAssertEqual(date.timeIntervalSinceNow, 0, accuracy: 60)
        XCTAssertNil(WidgetRestart.installDate(of: URL(fileURLWithPath: "/nowhere/at/all")))
    }

    func testTheAppItselfIsNotStale() throws {
        // It started after its own file was written, as a widget started after an update did.
        let executable = try XCTUnwrap(Bundle.main.executableURL)
        let installed = try XCTUnwrap(WidgetRestart.installDate(of: executable))
        let own = try XCTUnwrap(WidgetRestart.processes(running: executable).first { $0.id == getpid() })
        XCTAssertFalse(WidgetRestart.isStale(own, installed: installed))
    }
}
