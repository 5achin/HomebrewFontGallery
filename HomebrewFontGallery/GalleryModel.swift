import Foundation
import Observation

/// The list of fonts, the current selection, and the one install or uninstall in progress.
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

        var title: String {
            if isCancelling { return "Cancelling…" }
            switch kind {
            case .installing: return "Installing…"
            case .uninstalling: return "Uninstalling…"
            }
        }
    }

    /// How the last install or uninstall ended.
    struct Status: Equatable {
        enum Kind {
            case success
            case cancelled
            case failure
        }

        let token: String
        let kind: Kind
        let title: String
        let message: String
    }

    private(set) var fonts: [FontCask] = []
    private(set) var loadState = LoadState.loading
    private(set) var activity: Activity?
    private(set) var status: Status?

    /// The most common kinds of font, worked out from the fonts' names when the list loads.
    private(set) var categories: [FontCategory] = []
    static let categoryLimit = 8

    var selection: FontCask.ID?
    /// The category chosen in the sidebar, or nil for all fonts.
    var category: FontCategory.ID?
    var searchText = ""
    var filter = Filter.all

    private let brew: BrewService
    private var task: Task<Void, Never>?

    init(brew: BrewService = BrewService()) {
        self.brew = brew
    }

    var selectedFont: FontCask? {
        selection.flatMap { token in fonts.first { $0.token == token } }
    }

    var isBusy: Bool { activity != nil }

    var visibleFonts: [FontCask] {
        GalleryModel.filter(fonts, by: filter, searchText: searchText, category: categories.first { $0.id == category })
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
            loadState = .loaded
        } catch BrewError.notInstalled {
            loadState = .homebrewMissing
        } catch {
            loadState = .failed
        }
    }

    // MARK: Installing and uninstalling

    func install(_ font: FontCask) {
        guard !isBusy, font.isInstallable, !font.isInstalled else { return }
        start(Activity(token: font.token, name: font.name, kind: .installing)) { [brew] in
            try await brew.install(token: font.token)
            guard let current = try await brew.font(token: font.token), current.isInstalled else {
                throw BrewError.unreadableOutput
            }
            return current
        }
    }

    /// Call only after the user has confirmed.
    func uninstall(_ font: FontCask) {
        guard !isBusy, !font.needsInstaller else { return }
        start(Activity(token: font.token, name: font.name, kind: .uninstalling)) { [brew] in
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
    }

    /// Call only after the user has confirmed.
    func cancelActivity() {
        guard activity != nil, activity?.isCancelling == false else { return }
        activity?.isCancelling = true
        task?.cancel()
    }

    private func start(_ newActivity: Activity, operation: @escaping () async throws -> FontCask) {
        activity = newActivity
        status = nil
        task = Task {
            let outcome: Status
            do {
                replace(try await operation())
                outcome = GalleryModel.successStatus(for: newActivity)
            } catch {
                // Whatever happened, show what Homebrew now says about the font.
                if let current = try? await brew.font(token: newActivity.token) {
                    replace(current)
                }
                let wasCancelled = (error as? BrewError) == .cancelled || activity?.isCancelling == true
                outcome = wasCancelled
                    ? GalleryModel.cancelledStatus(for: newActivity, font: fonts.first { $0.token == newActivity.token })
                    : GalleryModel.failureStatus(for: newActivity)
            }
            status = outcome
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
            return Status(token: activity.token, kind: .success, title: "Installed",
                          message: "“\(activity.name)” is ready to use. Reopen an app to see it in its font menu.")
        case .uninstalling:
            return Status(token: activity.token, kind: .success, title: "Uninstalled",
                          message: "“\(activity.name)” was removed from this Mac.")
        }
    }

    nonisolated static func cancelledStatus(for activity: Activity, font: FontCask?) -> Status {
        let isInstalled = font?.isInstalled ?? (activity.kind == .uninstalling)
        return Status(token: activity.token, kind: .cancelled,
                      title: activity.kind == .installing ? "Installation Stopped" : "Uninstall Stopped",
                      message: isInstalled ? "“\(activity.name)” is still installed." : "“\(activity.name)” is not installed.")
    }

    nonisolated static func failureStatus(for activity: Activity) -> Status {
        switch activity.kind {
        case .installing:
            return Status(token: activity.token, kind: .failure, title: "Couldn’t Install “\(activity.name)”",
                          message: "Homebrew reported a problem. Check your internet connection and try again, or choose Help > Show Logs in Finder for details.")
        case .uninstalling:
            return Status(token: activity.token, kind: .failure, title: "Couldn’t Uninstall “\(activity.name)”",
                          message: "Homebrew reported a problem. Try again, or choose Help > Show Logs in Finder for details.")
        }
    }
}
