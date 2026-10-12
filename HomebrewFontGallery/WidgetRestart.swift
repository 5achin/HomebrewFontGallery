import Darwin
import Foundation
import WidgetKit

/// Restarts the app's widget when it is still running from before the app was updated.
///
/// Replacing the app leaves the old widget process running after the files it was started
/// from have gone, and macOS goes on asking it to draw. Every widget on the desktop then
/// comes up blank until that process ends. So when the app starts, it ends any widget
/// process left from an older copy, and macOS starts the new one the next time it draws.
enum WidgetRestart {
    struct Process: Equatable {
        let id: pid_t
        let started: Date
        /// The file the process was started from, or nil when that file no longer exists,
        /// as after an update has moved the old app away and deleted it.
        let executable: String?
    }

    static let widgetName = "HomebrewFontGalleryWidget"

    static var widgetExecutable: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/PlugIns/\(widgetName).appex/Contents/MacOS/\(widgetName)")
    }

    static func restartIfStale() {
        endStaleProcesses(named: widgetName, current: widgetExecutable)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Ends the processes of that name left from an older copy, and returns them.
    @discardableResult
    static func endStaleProcesses(named name: String, current executable: URL) -> [Process] {
        let installed = installDate(of: executable)
        let stale = processes(named: name).filter { isStale($0, current: executable, installed: installed) }
        for process in stale {
            let result = kill(process.id, SIGTERM)
            RunLog.write("Ended the widget left from before the update (process \(process.id)): \(result == 0 ? "done" : String(cString: strerror(errno)))")
        }
        return stale
    }

    /// A widget whose file has gone is running a copy of the app that was replaced. So is one
    /// started from the present file's place before that file was put there. A widget
    /// running from somewhere else, such as a build of the app being worked on, is left alone.
    static func isStale(_ process: Process, current executable: URL, installed: Date?) -> Bool {
        guard let path = process.executable else { return true }
        guard same(path, executable.path), let installed else { return false }
        return process.started < installed
    }

    private static func same(_ first: String, _ second: String) -> Bool {
        URL(fileURLWithPath: first).resolvingSymlinksInPath().path == URL(fileURLWithPath: second).resolvingSymlinksInPath().path
    }

    /// When the file was written to this disk, which unlike its modification date
    /// isn't carried over from the Mac that built it.
    static func installDate(of file: URL) -> Date? {
        var info = stat()
        guard stat(file.path, &info) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.st_ctimespec.tv_sec) + TimeInterval(info.st_ctimespec.tv_nsec) / 1e9)
    }

    /// This user's running processes of the given name. They are found by name, because
    /// the system no longer knows the path of a process whose file has been deleted.
    static func processes(named name: String) -> [Process] {
        var ids = [pid_t](repeating: 0, count: 8192)
        let bytes = proc_listallpids(&ids, Int32(ids.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return [] }
        // PROC_PIDPATHINFO_MAXSIZE, which Swift can't see.
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return ids.prefix(Int(bytes) / MemoryLayout<pid_t>.size).compactMap { id in
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard id > 0, proc_pidinfo(id, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_uid == getuid() else { return nil }
            let processName = withUnsafeBytes(of: &info.pbi_name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            guard processName == name else { return nil }
            let length = proc_pidpath(id, &path, UInt32(path.count))
            let executable = length > 0 ? String(cString: path) : nil
            return Process(id: id,
                           started: Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1e6),
                           executable: executable.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil })
        }
    }
}
