import SwiftUI

struct ContentView: View {
    @State private var model = GalleryModel()
    @State private var confirmingUninstall: FontCask?
    @State private var confirmingCancel = false
    @State private var detailsHidden = false
    /// How many cards fit across the grid, for the arrow keys. It is kept outside the
    /// view's state so that resizing the window doesn't redraw the whole window.
    @State private var gridLayout = GridLayout()
    /// True when the grid is too narrow for the toolbar's filter tabs.
    @State private var isCompact = false
    /// False while the window is first opening, when the pane appears without resizing it.
    @State private var windowFollowsPane = false
    private static let detailsWidth: CGFloat = 400
    /// The font that was selected when the app was last used.
    @AppStorage("selectedFont") private var lastSelection = ""

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 260)
        } detail: {
            // Outside the navigation stack, the details pane runs the full height of the
            // window and the toolbar stops at the edge of the grid.
            NavigationStack {
                gallery
            }
            .inspector(isPresented: showingDetails) {
                if let font = model.selectedFont {
                    FontDetailView(font: font, activity: model.activity, status: model.status)
                        // A set width, so the toolbar can leave exactly that much room above it.
                        .inspectorColumnWidth(Self.detailsWidth)
                        // A stretch of toolbar as wide as the pane holds the font's action in the
                        // middle, and keeps the window's own buttons over the grid.
                        .toolbar {
                            if showingDetails.wrappedValue {
                                if #available(macOS 26.0, *) {
                                    ToolbarItem {
                                        paneToolbarGap
                                    }
                                    .sharedBackgroundVisibility(.hidden)
                                } else {
                                    ToolbarItem {
                                        paneToolbarGap
                                    }
                                }
                                ToolbarItem {
                                    primaryAction
                                        .frame(width: Self.actionWidth)
                                }
                                if #available(macOS 26.0, *) {
                                    ToolbarItem {
                                        paneToolbarGap
                                    }
                                    .sharedBackgroundVisibility(.hidden)
                                } else {
                                    ToolbarItem {
                                        paneToolbarGap
                                    }
                                }
                            }
                        }
                }
            }
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search Fonts")
        // On the window itself, so the fonts load once. On the grid, the load ran twice.
        .task {
            guard !AppDelegate.isRunningTests, ThumbnailExport.directory == nil else { return }
            await model.load()
            if model.selection == nil, !lastSelection.isEmpty {
                model.selection = lastSelection
            }
            // The window opens at the size it was left, pane included, so only later
            // changes to the pane resize it.
            try? await Task.sleep(for: .seconds(1))
            windowFollowsPane = true
        }
        .onChange(of: showingDetails.wrappedValue) { _, isShowing in
            resizeWindow(paneIsShowing: isShowing)
        }
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
            .navigationTitle("Homebrew Fonts Gallery")
            .navigationSubtitle(subtitle)
            .toolbar {
                // The filter is three tabs in the centre while there is room for them, and
                // folds into a menu when the grid is too narrow.
                if isCompact {
                    ToolbarItem {
                        Menu {
                            Picker("Show", selection: $model.filter) {
                                ForEach(GalleryModel.Filter.allCases) { filter in
                                    Text(filter.rawValue).tag(filter)
                                }
                            }
                            .pickerStyle(.inline)
                        } label: {
                            Label("Show", systemImage: "line.3.horizontal.decrease")
                        }
                        .help("Show all fonts, or only the ones that are installed or not installed.")
                    }
                } else {
                    ToolbarItem(placement: .principal) {
                        Picker("Show", selection: $model.filter) {
                            ForEach(GalleryModel.Filter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .help("Show all fonts, or only the ones that are installed or not installed.")
                    }
                }
                ToolbarItem {
                    Button {
                        detailsHidden.toggle()
                    } label: {
                        Label(detailsHidden ? "Show Details" : "Hide Details", systemImage: "sidebar.trailing")
                    }
                    .disabled(model.selectedFont == nil)
                    .help(detailsHidden ? "Show the selected font’s details." : "Hide the selected font’s details.")
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
            // The grid asks for one column at least. Beside the details pane the system
            // keeps it wider, at 340 pt, which is two columns.
            .frame(minWidth: Self.cardWidth + 64, minHeight: 460)
            .onChange(of: model.selection) { _, selection in
                if let selection {
                    lastSelection = selection
                    detailsHidden = false
                }
            }
    }

    /// The action is one width whatever its title, so the space beside it can be exact.
    private static let actionWidth: CGFloat = 112

    /// Empty toolbar on each side of the action, which centres it over the pane.
    private var paneToolbarGap: some View {
        Color.clear
            .frame(width: (Self.detailsWidth - Self.actionWidth - 26) / 2, height: 28)
            .fixedSize()
    }

    /// Widens the window by the pane's width as the pane slides out, and narrows it again as
    /// the pane goes, so the grid keeps its width and its cards stay where they are.
    private func resizeWindow(paneIsShowing: Bool) {
        guard windowFollowsPane,
              let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
              !window.styleMask.contains(.fullScreen) else { return }
        // Wait a moment, so the window's smallest size has caught up with the pane.
        DispatchQueue.main.async {
            var frame = window.frame
            frame.size.width += paneIsShowing ? Self.detailsWidth : -Self.detailsWidth
            frame.size.width = max(frame.size.width, window.minSize.width)
            if let screen = window.screen?.visibleFrame {
                // Stay on the screen: slide left if the right edge would go off it.
                frame.size.width = min(frame.size.width, screen.width)
                if frame.maxX > screen.maxX {
                    frame.origin.x = max(screen.minX, screen.maxX - frame.width)
                }
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                window.animator().setFrame(frame, display: true)
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
    private static let cardWidth = FontThumbnailView.side
    private static let cardSpacing: CGFloat = 20
    /// Below this width of grid, the title and the filter tabs no longer fit side by side.
    private static let compactWidth: CGFloat = 620

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
                    }
                }
                .padding(24)
                .background {
                    GeometryReader { geometry in
                        Color.clear.onChange(of: geometry.size.width, initial: true) { _, width in
                            gridLayout.columnCount = Self.columnCount(forWidth: width - 48)
                            // This only changes as the width crosses one point, so it is cheap.
                            let compact = width < Self.compactWidth
                            if compact != isCompact {
                                isCompact = compact
                            }

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
        case .up: step = -gridLayout.columnCount
        case .down: step = gridLayout.columnCount
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

/// Plain storage for the grid's column count. Changing it redraws nothing.
private final class GridLayout {
    var columnCount = 3
}
