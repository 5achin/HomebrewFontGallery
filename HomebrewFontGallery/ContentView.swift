import SwiftUI

struct ContentView: View {
    @State private var model = GalleryModel()
    @State private var confirmingUninstall: FontCask?
    @State private var confirmingCancel = false
    @State private var detailsHidden = false
    @State private var columnCount = 3
    /// The font that was selected when the app was last used.
    @AppStorage("selectedFont") private var lastSelection = ""

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 260)
        } detail: {
            gallery
        }
        // Searching from the sidebar leaves the far right of the toolbar to the font's action.
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search Fonts")
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $model.category) {
            Label("All Fonts", systemImage: "square.grid.2x2")
                .badge(model.fonts.count)
                .tag(FontCategory.ID?.none)
            if !model.categories.isEmpty {
                Section("Categories") {
                    ForEach(model.categories) { category in
                        Label(category.word, systemImage: "textformat")
                            .badge(category.count)
                            .tag(FontCategory.ID?.some(category.id))
                    }
                }
            }
        }
    }

    // MARK: Gallery

    private var gallery: some View {
        content
            .inspector(isPresented: showingDetails) {
                if let font = model.selectedFont {
                    FontDetailView(font: font, activity: model.activity, status: model.status)
                        .inspectorColumnWidth(min: 340, ideal: 400, max: 560)
                }
            }
            .navigationTitle("Homebrew Fonts Gallery")
            .navigationSubtitle(subtitle)
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
                    Button {
                        detailsHidden.toggle()
                    } label: {
                        Label(detailsHidden ? "Show Details" : "Hide Details", systemImage: "sidebar.trailing")
                    }
                    .disabled(model.selectedFont == nil)
                    .help(detailsHidden ? "Show the selected font’s details." : "Hide the selected font’s details.")
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
            .frame(minWidth: 760, minHeight: 460)
            .task {
                guard !AppDelegate.isRunningTests, ThumbnailExport.directory == nil else { return }
                await model.load()
                if model.selection == nil, !lastSelection.isEmpty {
                    model.selection = lastSelection
                }
            }
            .onChange(of: model.selection) { _, selection in
                if let selection {
                    lastSelection = selection
                    detailsHidden = false
                }
            }
    }

    /// The details pane slides out whenever a font is selected, unless it has been hidden.
    private var showingDetails: Binding<Bool> {
        Binding(
            get: { model.selectedFont != nil && !detailsHidden },
            set: { detailsHidden = !$0 }
        )
    }

    private var subtitle: String {
        guard model.loadState == .loaded else { return "" }
        let count = model.visibleFonts.count
        return count == 1 ? "1 font" : "\(count.formatted()) fonts"
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .loading:
            ProgressView("Loading Fonts…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .homebrewMissing:
            ContentUnavailableView {
                Label("Homebrew Isn’t Installed", systemImage: "shippingbox")
            } description: {
                Text("Homebrew Fonts Gallery uses Homebrew to find and install fonts. Install Homebrew, then try again.")
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
            grid
        }
    }

    // MARK: Grid

    /// Every card is this wide, the size of Font Book's, whatever the window's size.
    /// A wider window fits more cards across, and the rest reflow.
    private static let cardWidth: CGFloat = 116
    private static let cardSpacing: CGFloat = 20

    /// How many cards an adaptive grid fits across the given width.
    static func columnCount(forWidth width: CGFloat) -> Int {
        max(1, Int((width + cardSpacing) / (cardWidth + cardSpacing)))
    }

    private var grid: some View {
        let fonts = model.visibleFonts
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.cardWidth, maximum: Self.cardWidth), spacing: Self.cardSpacing)], spacing: 12) {
                    ForEach(fonts) { font in
                        Button {
                            model.selection = font.token
                            detailsHidden = false
                        } label: {
                            FontThumbnailView(font: font, isSelected: model.selection == font.token,
                                              isBusy: model.activity?.token == font.token)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(font.isInstalled ? "\(font.name), installed" : font.name)
                        .accessibilityAddTraits(model.selection == font.token ? .isSelected : [])
                        .id(font.token)
                    }
                }
                .padding(24)
                .background {
                    GeometryReader { geometry in
                        Color.clear.onChange(of: geometry.size.width, initial: true) { _, width in
                            columnCount = Self.columnCount(forWidth: width - 48)
                        }
                    }
                }
            }
            // A different category is a different set of fonts, so its grid starts again from the top.
            .id(model.category ?? "")
            .focusable()
            .focusEffectDisabled()
            .onMoveCommand { direction in
                moveSelection(direction, in: fonts, proxy: proxy)
            }
            .onExitCommand {
                model.selection = nil
            }
            .onAppear {
                // Bring the restored selection into view once the grid has its thumbnails.
                guard let selection = model.selection ?? (lastSelection.isEmpty ? nil : lastSelection) else { return }
                Task {
                    // The grid only estimates where a far-off card is, so the first jump can land
                    // short. A second one, once the cards near it exist, lands on it.
                    proxy.scrollTo(selection, anchor: .center)
                    try? await Task.sleep(for: .milliseconds(300))
                    proxy.scrollTo(selection, anchor: .center)
                }
            }
            .overlay {
                if fonts.isEmpty {
                    if model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                        ContentUnavailableView("No Fonts", systemImage: "textformat",
                                               description: Text(model.filter == .installed ? "Fonts you install appear here." : "There are no fonts to show."))
                    } else {
                        ContentUnavailableView.search(text: model.searchText)
                    }
                }
            }
        }
    }

    /// Moves the selection with the arrow keys, a column or a row at a time.
    private func moveSelection(_ direction: MoveCommandDirection, in fonts: [FontCask], proxy: ScrollViewProxy) {
        guard !fonts.isEmpty else { return }
        guard let current = fonts.firstIndex(where: { $0.token == model.selection }) else {
            model.selection = fonts[0].token
            return
        }
        let step: Int
        switch direction {
        case .left: step = -1
        case .right: step = 1
        case .up: step = -columnCount
        case .down: step = columnCount
        @unknown default: return
        }
        let target = current + step
        guard fonts.indices.contains(target) else { return }
        model.selection = fonts[target].token
        proxy.scrollTo(fonts[target].token)
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
            .buttonStyle(.borderedProminent)
            .tint(.red)
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
            .buttonStyle(.borderedProminent)
            .tint(.green)
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
