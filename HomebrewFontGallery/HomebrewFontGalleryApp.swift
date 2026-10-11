import SwiftUI

@main
struct HomebrewFontGalleryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Homebrew Fonts Gallery", id: "main") {
            ContentView()
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(after: .help) {
                Button("Show Logs in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([RunLog.fileURL])
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// True while the unit tests are using the app as their host, when it should stay idle.
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let directory = ThumbnailExport.directory {
            ThumbnailExport.run(to: directory)
            return
        }
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        if !AppDelegate.isRunningTests {
            FontPreview.removeDownloads()
            FontThumbnails.removeOutdated()
        }
        RunLog.write("=== Homebrew Fonts Gallery \(version) (\(build)) launched from \(Bundle.main.bundlePath), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        FontPreview.removeDownloads()
        RunLog.write("Quit")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
