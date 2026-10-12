import Foundation
import Observation

/// The list of fonts, the current selection, and the installs or uninstalls in progress.
@MainActor
@Observable
final class GalleryModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case homebrewMissing
        case failed
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case installed = "Installed"
        case notInstalled = "Not Installed"

        var id: Self { self }
    }

    /// An install or uninstall that is running now.
    struct Activity: Equatable {
        enum Kind {
            case installing
            case uninstalling
        }

        let token: String
        let name: String
        let kind: Kind
        var isCancelling = false
        /// Where this font comes among the fonts being worked through, counting from one.
        var position = 1
        var total = 1

        var title: String {
            if isCancelling { return "Cancelling…" }
            switch kind {
            case .installing: return "Installing…"
            case .uninstalling: return "Uninstalling…"
            }
        }
    }

    /// How the last install or uninstall ended, for one font or for several.
    struct Status: Equatable {
        enum Kind {
            case success
            case cancelled
            case failure
        }

        let tokens: Set<String>
        let kind: Kind
        let title: String
        let message: String
    }

    /// What the action button does to the selected fonts.
    struct SelectionAction: Equatable {
        enum Kind {
            case install
            case uninstall
        }

        let kind: Kind
        /// The selected fonts the action applies to. Empty when it can't be done to any.
        let fonts: [FontCask]
        /// True when more than one font is selected.
        let isMultiple: Bool

        var title: String {
            let verb = kind == .install ? "Install" : "Uninstall"
            guard isMultiple, !fonts.isEmpty else { return verb }
            return fonts.count == 1 ? "\(verb) 1 Font" : "\(verb) \(fonts.count.formatted()) Fonts"
        }
    }

    private(set) var fonts: [FontCask] = [] {
        didSet {
            installedCount = fonts.lazy.filter(\.isInstalled).count
            updateSelectedFont()
            updateVisibleFonts()
        }
    }
    private(set) var loadState = LoadState.loading
    private(set) var activity: Activity?
    private(set) var status: Status?

    /// The most common kinds of font, worked out from the fonts' names when the list loads.
    private(set) var categories: [FontCategory] = []
    static let categoryLimit = 8

    /// The selected fonts. Several can be selected, to install or uninstall them together.
    var selection: Set<FontCask.ID> = [] {
        didSet {
            if selection != oldValue { updateSelectedFont() }
        }
    }
    /// What is chosen in the sidebar.
    var section = Section.all {
        didSet { updateVisibleFonts() }
    }
    var searchText = "" {
        didSet { updateVisibleFonts() }
    }

    /// One row of the sidebar: every font, the installed or not-installed ones, or a category.
    enum Section: Hashable {
        case all
        case installed
        case notInstalled
        case category(FontCategory.ID)
    }

    /// Selects one font and makes sure the grid is showing it, whatever was being
    /// searched for or filtered. It does nothing for a font Homebrew doesn't list.
    @discardableResult
    func show(_ token: FontCask.ID) -> Bool {
        guard fonts.contains(where: { $0.token == token }) else { return false }
        if !visibleFonts.contains(where: { $0.token == token }) {
            searchText = ""
            section = .all
        }
        selection = [token]
        return true
    }

    private let brew: BrewService
    private var task: Task<Void, Never>?

    init(brew: BrewService = BrewService()) {
        self.brew = brew
    }

    /// The selected fonts, in the list's order. They are looked up when the selection or
    /// the fonts change, and kept, because several views read them every time they are redrawn.
    private(set) var selectedFonts: [FontCask] = []
    /// The selected font, when exactly one is selected.
    private(set) var selectedFont: FontCask?
    /// What the action button would do now, or nil when nothing is selected.
    private(set) var selectionAction: SelectionAction?
    private(set) var installedCount = 0

    private func updateSelectedFont() {
        let found = selection.isEmpty ? [] : fonts.filter { selection.contains($0.token) }
        guard found != selectedFonts else { return }
        selectedFonts = found
        let single = found.count == 1 ? found[0] : nil
        if single != selectedFont {
            selectedFont = single
        }
        selectionAction = GalleryModel.action(for: found)
    }

    /// Installs whatever in the selection isn't installed yet. Only when every selected
    /// font is installed already does the action become Uninstall.
    nonisolated static func action(for selected: [FontCask]) -> SelectionAction? {
        guard !selected.isEmpty else { return nil }
        let isMultiple = selected.count > 1
        if selected.allSatisfy(\.isInstalled) {
            return SelectionAction(kind: .uninstall, fonts: selected.filter { !$0.needsInstaller }, isMultiple: isMultiple)
        }
        return SelectionAction(kind: .install, fonts: selected.filter { !$0.isInstalled && $0.isInstallable },
                               isMultiple: isMultiple)
    }

    var isBusy: Bool { activity != nil }

    /// The fonts the grid shows. It is worked out when what it depends on changes, and
    /// kept, because the window asks for it many times a second while it is resized.
    private(set) var visibleFonts: [FontCask] = []
    /// Goes up each time `visibleFonts` is worked out again, so a view can tell that it
    /// changed without comparing 2,583 fonts.
    private(set) var visibleFontsVersion = 0

    private func updateVisibleFonts() {
        visibleFontsVersion += 1
        let filter: Filter
        var category: FontCategory?
        switch section {
        case .all: filter = .all
        case .installed: filter = .installed
        case .notInstalled: filter = .notInstalled
        case .category(let id):
            filter = .all
            category = categories.first { $0.id == id }
        }
        visibleFonts = GalleryModel.filter(fonts, by: filter, searchText: searchText, category: category)
    }

    nonisolated static func filter(_ fonts: [FontCask], by filter: Filter, searchText: String,
                                   category: FontCategory? = nil) -> [FontCask] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return fonts.filter { font in
            if let category, !category.contains(font) { return false }
            switch filter {
            case .all: break
            case .installed: if !font.isInstalled { return false }
            case .notInstalled: if font.isInstalled { return false }
            }
            guard !query.isEmpty else { return true }
            return ([font.name, font.token] + font.alternateNames).contains { $0.localizedStandardContains(query) }
        }
    }

    // MARK: Loading

    func load() async {
        loadState = .loading
        do {
            let all = try await brew.allFonts()
            // Leave out fonts that can never be installed from here, unless one is already installed.
            fonts = all
                .filter { $0.isInstallable || $0.isInstalled }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            categories = FontCategory.top(GalleryModel.categoryLimit, in: fonts)
            updateVisibleFonts()
            loadState = .loaded
        } catch BrewError.notInstalled {
            loadState = .homebrewMissing
        } catch {
            // A load that was cancelled hasn't failed: the window started another in its
            // place, and that one decides what to show.
            guard !Task.isCancelled, (error as? BrewError) != .cancelled else { return }
            loadState = .failed
        }
    }

    // MARK: Installing and uninstalling

    func install(_ font: FontCask) {
        install([font])
    }

    /// Installs the fonts one after another, leaving out any that are installed already.
    func install(_ batch: [FontCask]) {
        run(batch.filter { $0.isInstallable && !$0.isInstalled }, kind: .installing)
    }

    /// Call only after the user has confirmed.
    func uninstall(_ font: FontCask) {
        uninstall([font])
    }

    /// Uninstalls the fonts one after another. Call only after the user has confirmed.
    func uninstall(_ batch: [FontCask]) {
        run(batch.filter { !$0.needsInstaller }, kind: .uninstalling)
    }

    /// Call only after the user has confirmed. Stops the font being worked on, and any still waiting.
    func cancelActivity() {
        guard activity != nil, activity?.isCancelling == false else { return }
        activity?.isCancelling = true
        task?.cancel()
    }

    private func install(_ font: FontCask, with brew: BrewService) async throws -> FontCask {
        try await brew.install(token: font.token)
        guard let current = try await brew.font(token: font.token), current.isInstalled else {
            throw BrewError.unreadableOutput
        }
        return current
    }

    private func uninstall(_ font: FontCask, with brew: BrewService) async throws -> FontCask {
        // The font may have been removed in Terminal since the list loaded.
        guard let before = try await brew.font(token: font.token) else {
            throw BrewError.unreadableOutput
        }
        guard before.isInstalled else { return before }
        try await brew.uninstall(token: font.token)
        guard let after = try await brew.font(token: font.token), !after.isInstalled else {
            throw BrewError.unreadableOutput
        }
        return after
    }

    /// Works through the fonts in turn. One that fails doesn't stop the rest; cancelling does.
    private func run(_ batch: [FontCask], kind: Activity.Kind) {
        guard !isBusy, let first = batch.first else { return }
        func step(_ index: Int) -> Activity {
            Activity(token: batch[index].token, name: batch[index].name, kind: kind, position: index + 1, total: batch.count)
        }
        activity = step(0)
        status = nil
        task = Task {
            var finished: [FontCask] = []
            var failed: [FontCask] = []
            var wasCancelled = false
            var last = step(0)
            for (index, font) in batch.enumerated() {
                last = step(index)
                activity = last
                do {
                    switch kind {
                    case .installing: replace(try await install(font, with: brew))
                    case .uninstalling: replace(try await uninstall(font, with: brew))
                    }
                    finished.append(font)
                } catch {
                    // Whatever happened, show what Homebrew now says about the font.
                    if let current = try? await brew.font(token: font.token) {
                        replace(current)
                    }
                    if (error as? BrewError) == .cancelled || activity?.isCancelling == true {
                        wasCancelled = true
                        break
                    }
                    failed.append(font)
                }
                if activity?.isCancelling == true, index + 1 < batch.count {
                    wasCancelled = true
                    break
                }
            }
            if batch.count == 1 {
                status = wasCancelled
                    ? GalleryModel.cancelledStatus(for: last, font: fonts.first { $0.token == first.token })
                    : failed.isEmpty ? GalleryModel.successStatus(for: last) : GalleryModel.failureStatus(for: last)
            } else {
                status = GalleryModel.batchStatus(kind: kind, batch: batch, finished: finished, failed: failed,
                                                  wasCancelled: wasCancelled)
            }
            activity = nil
            task = nil
        }
    }

    private func replace(_ font: FontCask) {
        guard let index = fonts.firstIndex(where: { $0.token == font.token }) else { return }
        fonts[index] = font
    }

    // MARK: Messages

    nonisolated static func successStatus(for activity: Activity) -> Status {
        switch activity.kind {
        case .installing:
            return Status(tokens: [activity.token], kind: .success, title: "Installed",
                          message: "“\(activity.name)” is ready to use. Reopen an app to see it in its font menu.")
        case .uninstalling:
            return Status(tokens: [activity.token], kind: .success, title: "Uninstalled",
                          message: "“\(activity.name)” was removed from this Mac.")
        }
    }

    nonisolated static func cancelledStatus(for activity: Activity, font: FontCask?) -> Status {
        let isInstalled = font?.isInstalled ?? (activity.kind == .uninstalling)
        return Status(tokens: [activity.token], kind: .cancelled,
                      title: activity.kind == .installing ? "Installation Stopped" : "Uninstall Stopped",
                      message: isInstalled ? "“\(activity.name)” is still installed." : "“\(activity.name)” is not installed.")
    }

    nonisolated static func failureStatus(for activity: Activity) -> Status {
        switch activity.kind {
        case .installing:
            return Status(tokens: [activity.token], kind: .failure, title: "Couldn’t Install “\(activity.name)”",
                          message: "Homebrew reported a problem. Check your internet connection and try again, or choose Help > Show Logs in Finder for details.")
        case .uninstalling:
            return Status(tokens: [activity.token], kind: .failure, title: "Couldn’t Uninstall “\(activity.name)”",
                          message: "Homebrew reported a problem. Try again, or choose Help > Show Logs in Finder for details.")
        }
    }

    /// How installing or uninstalling several fonts ended.
    nonisolated static func batchStatus(kind: Activity.Kind, batch: [FontCask], finished: [FontCask], failed: [FontCask],
                                        wasCancelled: Bool) -> Status {
        let tokens = Set(batch.map(\.token))
        let done = kind == .installing ? "Installed" : "Uninstalled"
        let verb = kind == .installing ? "Install" : "Uninstall"
        let count = finished.count == batch.count
            ? fontCount(batch.count)
            : "\(finished.count.formatted()) of \(fontCount(batch.count))"
        if wasCancelled {
            return Status(tokens: tokens, kind: .cancelled,
                          title: kind == .installing ? "Installation Stopped" : "Uninstall Stopped",
                          message: "\(done) \(count) before stopping.")
        }
        if failed.isEmpty {
            return Status(tokens: tokens, kind: .success, title: "\(done) \(count.capitalized)",
                          message: kind == .installing
                              ? "They are ready to use. Reopen an app to see them in its font menu."
                              : "They were removed from this Mac.")
        }
        let names = ListFormatter.localizedString(byJoining: failed.prefix(3).map { "“\($0.name)”" }
            + (failed.count > 3 ? ["\((failed.count - 3).formatted()) more"] : []))
        return Status(tokens: tokens, kind: .failure, title: "Couldn’t \(verb) \(fontCount(failed.count).capitalized)",
                      message: "\(done) \(count). Homebrew reported a problem with \(names). Try again, or choose Help > Show Logs in Finder for details.")
    }

    nonisolated static func fontCount(_ count: Int) -> String {
        count == 1 ? "1 font" : "\(count.formatted()) fonts"
    }
}
