import XCTest
@testable import HomebrewFontGallery

final class WidgetRestartTests: XCTestCase {
    private let current = URL(fileURLWithPath: "/Applications/App.app/Contents/PlugIns/Widget.appex/Contents/MacOS/Widget")
    private let installed = Date(timeIntervalSince1970: 1_000_000)

    private func process(started offset: TimeInterval, from executable: String?) -> WidgetRestart.Process {
        WidgetRestart.Process(id: 1, started: installed.addingTimeInterval(offset), executable: executable)
    }

    func testAWidgetWhoseFileHasGoneIsStale() {
        // What an update leaves: the old app was moved away and deleted under the widget.
        XCTAssertTrue(WidgetRestart.isStale(process(started: -4, from: nil), current: current, installed: installed))
        XCTAssertTrue(WidgetRestart.isStale(process(started: 60, from: nil), current: current, installed: installed))
    }

    func testAWidgetFromBeforeItsFileWasReplacedIsStale() {
        XCTAssertTrue(WidgetRestart.isStale(process(started: -60, from: current.path), current: current, installed: installed))
        XCTAssertFalse(WidgetRestart.isStale(process(started: 60, from: current.path), current: current, installed: installed))
        XCTAssertFalse(WidgetRestart.isStale(process(started: -60, from: current.path), current: current, installed: nil))
    }

    func testAWidgetRunningFromAnotherCopyIsLeftAlone() {
        let build = "/Users/someone/Developer/build/App.app/Contents/PlugIns/Widget.appex/Contents/MacOS/Widget"
        XCTAssertFalse(WidgetRestart.isStale(process(started: -60, from: build), current: current, installed: installed))
    }

    func testFindsARunningProcessByItsName() throws {
        // The app the tests run inside stands in for the widget.
        let executable = try XCTUnwrap(Bundle.main.executableURL)
        let own = try XCTUnwrap(WidgetRestart.processes(named: executable.lastPathComponent).first { $0.id == getpid() })
        XCTAssertLessThan(own.started, Date())
        XCTAssertGreaterThan(own.started, Date().addingTimeInterval(-3600))
        XCTAssertEqual(own.executable.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path },
                       executable.resolvingSymlinksInPath().path)
        XCTAssertEqual(WidgetRestart.processes(named: "NoSuchProcessAtAll"), [])
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
        let executable = try XCTUnwrap(Bundle.main.executableURL)
        let installed = WidgetRestart.installDate(of: executable)
        let own = try XCTUnwrap(WidgetRestart.processes(named: executable.lastPathComponent).first { $0.id == getpid() })
        XCTAssertFalse(WidgetRestart.isStale(own, current: executable, installed: installed))
    }
}
