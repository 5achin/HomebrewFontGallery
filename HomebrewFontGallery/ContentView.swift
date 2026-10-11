import SwiftUI

struct ContentView: View {
    @State private var model = GalleryModel()
    /// What the window is showing, shared with the grid.
    @State private var window = WindowState()
    /// False while the window is first opening, when the pane appears without resizing it.
    @State private var windowFollowsPane = false
    private static let detailsWidth: CGFloat = 400
    /// The font that was selected when the app was last used.
    @AppStorage("selectedFont") private var lastSelection = ""

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            // Outside the navigation stack, the details pane runs the full height of the
            // window and the toolbar stops at the edge of the grid.
            NavigationStack {
                gallery
            }
            .inspector(isPresented: showingDetails) {
                if let font = model.selectedFont {
                    DetailsPane(model: model, font: font)
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
                                    FontActionButton(model: model, window: window)
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
            // The pane appears and goes at once, with the window resized in the same moment.
            // Sliding it re-laid out the grid on every frame, which was choppy.
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search Fonts")
        // On the window itself, so the fonts load once. On the grid, the load ran twice.
        .task {
            guard !AppDelegate.isRunningTests, ThumbnailExport.directory == nil else { return }
            await model.load()
            if model.selection == nil, !lastSelection.isEmpty {
                WindowState.withoutAnimation {
                    model.selection = lastSelection
                }
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

    // MARK: Gallery

    private var gallery: some View {
        content
            .navigationTitle("Homebrew Fonts Gallery")
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItem {
                    Button {
                        WindowState.withoutAnimation {
                            window.detailsHidden.toggle()
                        }
                    } label: {
                        Label(window.detailsHidden ? "Show Details" : "Hide Details", systemImage: "sidebar.trailing")
                    }
                    .disabled(model.selectedFont == nil)
                    .help(window.detailsHidden ? "Show the selected font’s details." : "Hide the selected font’s details.")
                }
            }
            .confirmationDialog(
                "Uninstall “\(window.confirmingUninstall?.name ?? "")”?",
                isPresented: Binding(get: { window.confirmingUninstall != nil }, set: { if !$0 { window.confirmingUninstall = nil } }),
                presenting: window.confirmingUninstall
            ) { font in
                Button("Uninstall", role: .destructive) {
                    model.uninstall(font)
                }
                Button("Cancel", role: .cancel) {}
            } message: { font in
                Text("Homebrew will remove \(Self.fileCount(font)) from your Fonts folder. Documents that use the font will show a different one until you install it again.")
            }
            .confirmationDialog(cancelTitle, isPresented: $window.confirmingCancel) {
                Button(stopLabel, role: .destructive) {
                    model.cancelActivity()
                }
                Button(keepLabel, role: .cancel) {}
            } message: {
                Text(cancelMessage)
            }
            // The grid asks for one column at least. Beside the details pane the system
            // keeps it wider, at 340 pt, which is two columns.
            .frame(minWidth: FontCollection.cardSide + 64, minHeight: 460)
            .onChange(of: model.selection) { _, selection in
                if let selection {
                    lastSelection = selection
                    window.detailsHidden = false
                }
            }
    }

    /// The action is one width whatever its title, so the space beside it can be exact.
    private static let actionWidth: CGFloat = 140

    /// Empty toolbar on each side of the action, which centres it over the pane.
    private var paneToolbarGap: some View {
        Color.clear
            .frame(width: (Self.detailsWidth - Self.actionWidth - 26) / 2, height: 28)
            .fixedSize()
    }

    /// Widens the window by the pane's width as the pane appears, and narrows it again as
    /// the pane goes, so the grid keeps its width and its cards stay where they are.
    private func resizeWindow(paneIsShowing: Bool) {
        guard windowFollowsPane,
              let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
              !window.styleMask.contains(.fullScreen),
              // Hiding the pane must leave room for the sidebar and two columns of cards.
              paneIsShowing || window.frame.width - Self.detailsWidth >= 500 else { return }
        var frame = window.frame
        frame.size.width += paneIsShowing ? Self.detailsWidth : -Self.detailsWidth
        if let screen = window.screen?.visibleFrame {
            // Stay on the screen: slide left if the right edge would go off it.
            frame.size.width = min(frame.size.width, screen.width)
            if frame.maxX > screen.maxX {
                frame.origin.x = max(screen.minX, screen.maxX - frame.width)
            }
        }
        // In the same turn as the pane, and without laying out yet, so the window is laid
        // out once with both changes and the grid never sees a different width.
        window.setFrame(frame, display: false)
    }

    /// The details pane slides out whenever a font is selected, unless it has been hidden.
    private var showingDetails: Binding<Bool> {
        Binding(
            get: { model.selectedFont != nil && !window.detailsHidden },
            set: { window.detailsHidden = !$0 }
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
            FontGrid(model: model, window: window)
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
