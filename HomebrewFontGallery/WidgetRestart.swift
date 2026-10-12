import Darwin
import Foundation
import WidgetKit

/// Restarts the app's widget when it is still running from before the app was updated.
///
/// Replacing the app leaves the old widget process running without the files it was started
/// from, and macOS goes on asking it to draw. Every widget on the desktop then comes up blank
/// until that process ends. So when the app starts, it ends any widget process older than
/// the widget now inside the app, and macOS starts the new one the next time it draws.
enum WidgetRestart {
    struct Process: Equatable {
        let id: pid_t
        let started: Date
    }

    static var widgetExecutable: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/PlugIns/HomebrewFontGalleryWidget.appex/Contents/MacOS/HomebrewFontGalleryWidget")
    }

    static func restartIfStale() {
        endStaleProcesses(of: widgetExecutable)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Ends the processes started from the file before the file was put in place, and returns them.
    @discardableResult
    static func endStaleProcesses(of executable: URL) -> [Process] {
        guard let installed = installDate(of: executable) else { return [] }
        let stale = processes(running: executable).filter { isStale($0, installed: installed) }
        for process in stale {
            let result = kill(process.id, SIGTERM)
            RunLog.write("Ended the widget left from before the update (process \(process.id)): \(result == 0 ? "done" : String(cString: strerror(errno)))")
        }
        return stale
    }

    /// A process started before the widget's file was put in place is running the old widget.
    static func isStale(_ process: Process, installed: Date) -> Bool {
        process.started < installed
    }

    /// When the file was written to this disk, which unlike its modification date
    /// isn't carried over from the Mac that built it.
    static func installDate(of file: URL) -> Date? {
        var info = stat()
        guard stat(file.path, &info) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.st_ctimespec.tv_sec) + TimeInterval(info.st_ctimespec.tv_nsec) / 1e9)
    }

    /// The running processes that were started from the given file.
    static func processes(running executable: URL) -> [Process] {
        let wanted = executable.resolvingSymlinksInPath().path
        var ids = [pid_t](repeating: 0, count: 8192)
        let bytes = proc_listallpids(&ids, Int32(ids.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return [] }
        // PROC_PIDPATHINFO_MAXSIZE, which Swift can't see.
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return ids.prefix(Int(bytes) / MemoryLayout<pid_t>.size).compactMap { id in
            guard id > 0, proc_pidpath(id, &path, UInt32(path.count)) > 0,
                  URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath().path == wanted else { return nil }
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(id, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
            return Process(id: id, started: Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1e6))
        }
    }
}
