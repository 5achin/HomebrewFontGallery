import SwiftUI

struct ContentView: View {
    @State private var model = GalleryModel()
    @State private var confirmingUninstall: FontCask?
    @State private var confirmingCancel = false
    /// The font that was selected when the app was last used.
    @AppStorage("selectedFont") private var lastSelection = ""

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 400)
        } detail: {
            detail
        }
        .navigationTitle("Homebrew Font Gallery")
        .navigationSubtitle(subtitle)
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search Fonts")
        .toolbar {
            ToolbarItem {
                Picker("Show", selection: $model.filter) {
                    ForEach(GalleryModel.Filter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .help("Show all fonts, or only the ones that are installed or not installed.")
            }
            ToolbarItem(placement: .primaryAction) {
                primaryAction
            }
        }
        .confirmationDialog(
            "Uninstall “\(confirmingUninstall?.name ?? "")”?",
            isPresented: Binding(get: { confirmingUninstall != nil }, set: { if !$0 { confirmingUninstall = nil } }),
            presenting: confirmingUninstall
        ) { font in
            Button("Uninstall", role: .destructive) {
                model.uninstall(font)
            }
            Button("Cancel", role: .cancel) {}
        } message: { font in
            Text("Homebrew will remove \(Self.fileCount(font)) from your Fonts folder. Documents that use the font will show a different one until you install it again.")
        }
        .confirmationDialog(cancelTitle, isPresented: $confirmingCancel) {
            Button(stopLabel, role: .destructive) {
                model.cancelActivity()
            }
            Button(keepLabel, role: .cancel) {}
        } message: {
            Text(cancelMessage)
        }
        .frame(minWidth: 700, minHeight: 420)
        .task {
            guard !AppDelegate.isRunningTests else { return }
            await model.load()
            if model.selection == nil, !lastSelection.isEmpty {
                model.selection = lastSelection
            }
        }
        .onChange(of: model.selection) { _, selection in
            if let selection {
                lastSelection = selection
            }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        let fonts = model.visibleFonts
        return ScrollViewReader { proxy in
            fontList(fonts)
                .onChange(of: model.loadState) { _, state in
                    // Bring the restored selection into view once the list has its rows.
                    guard state == .loaded, !lastSelection.isEmpty else { return }
                    Task { proxy.scrollTo(lastSelection, anchor: .center) }
                }
        }
    }

    private func fontList(_ fonts: [FontCask]) -> some View {
        List(fonts, selection: $model.selection) { font in
            HStack {
                Text(font.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if model.activity?.token == font.token {
                    ProgressView()
                        .controlSize(.small)
                } else if font.isInstalled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Installed")
                        .help("Installed")
                }
            }
        }
        .overlay {
            if model.loadState == .loaded, fonts.isEmpty {
                if model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView("No Fonts", systemImage: "textformat",
                                           description: Text(model.filter == .installed ? "Fonts you install appear here." : "There are no fonts to show."))
                } else {
                    ContentUnavailableView.search(text: model.searchText)
                }
            }
        }
    }

    private var subtitle: String {
        guard model.loadState == .loaded else { return "" }
        let count = model.visibleFonts.count
        return count == 1 ? "1 font" : "\(count.formatted()) fonts"
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch model.loadState {
        case .loading:
            ProgressView("Loading Fonts…")
        case .homebrewMissing:
            ContentUnavailableView {
                Label("Homebrew Isn’t Installed", systemImage: "shippingbox")
            } description: {
                Text("Homebrew Font Gallery uses Homebrew to find and install fonts. Install Homebrew, then try again.")
            } actions: {
                Link("Get Homebrew", destination: URL(string: "https://brew.sh")!)
                Button("Try Again") {
                    Task { await model.load() }
                }
            }
        case .failed:
            ContentUnavailableView {
                Label("Couldn’t Load Fonts", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Homebrew didn’t return its list of fonts. Check your internet connection and try again, or choose Help > Show Logs in Finder for details.")
            } actions: {
                Button("Try Again") {
                    Task { await model.load() }
                }
            }
        case .loaded:
            if let font = model.selectedFont {
                FontDetailView(font: font, activity: model.activity, status: model.status)
            } else {
                ContentUnavailableView("No Font Selected", systemImage: "textformat",
                                       description: Text("Select a font to preview it."))
            }
        }
    }

    // MARK: Toolbar

    @ViewBuilder
    private var primaryAction: some View {
        if let activity = model.activity {
            Button {
                confirmingCancel = true
            } label: {
                Label("Cancel", systemImage: "xmark.circle")
            }
            .labelStyle(.titleAndIcon)
            .disabled(activity.isCancelling)
            .help(activity.kind == .installing ? "Stop installing “\(activity.name)”." : "Stop uninstalling “\(activity.name)”.")
        } else if let font = model.selectedFont, font.isInstalled {
            Button {
                confirmingUninstall = font
            } label: {
                Label("Uninstall", systemImage: "trash")
            }
            .labelStyle(.titleAndIcon)
            .disabled(font.needsInstaller)
            .help("Remove “\(font.name)” from this Mac.")
        } else {
            Button {
                if let font = model.selectedFont {
                    model.install(font)
                }
            } label: {
                Label("Install", systemImage: "arrow.down.circle")
            }
            .labelStyle(.titleAndIcon)
            .keyboardShortcut(.defaultAction)
            .disabled(model.selectedFont?.isInstallable != true)
            .help(model.selectedFont.map { "Install “\($0.name)” on this Mac." } ?? "Select a font to install it.")
        }
    }

    // MARK: Confirmation text

    private static func fileCount(_ font: FontCask) -> String {
        switch font.fontFiles.count {
        case 0: return "this font"
        case 1: return "its font file"
        default: return "its \(font.fontFiles.count) font files"
        }
    }

    private var isInstalling: Bool { model.activity?.kind != .uninstalling }

    private var cancelTitle: String {
        let name = model.activity?.name ?? ""
        return isInstalling ? "Stop installing “\(name)”?" : "Stop uninstalling “\(name)”?"
    }

    private var cancelMessage: String {
        isInstalling
            ? "Homebrew will stop, and the font won’t be installed. You can install it again later."
            : "Homebrew will stop. If it has already removed some of the font’s files, uninstall it again to remove the rest."
    }

    private var stopLabel: String { isInstalling ? "Stop Installing" : "Stop Uninstalling" }
    private var keepLabel: String { isInstalling ? "Keep Installing" : "Keep Uninstalling" }
}
