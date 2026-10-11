import AppKit
import SwiftUI

/// The grid of font cards, drawn by AppKit's collection view.
///
/// A SwiftUI lazy grid walks its list from the first item to the visible ones every time
/// it is laid out, which for 2,583 fonts took tens of milliseconds, several times over,
/// whenever the window or the details pane changed size. A collection view lays out only
/// what is on screen, and gives arrow-key selection for free.
struct FontCollection: NSViewRepresentable {
    let model: GalleryModel
    let window: WindowState

    /// Every card is this wide, the size of Font Book's, whatever the window's size.
    static let cardSide: CGFloat = 116
    static let itemSize = NSSize(width: cardSide, height: cardSide + 8 + 32)
    static let inset: CGFloat = 24

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = FontCollection.itemSize
        layout.minimumInteritemSpacing = 20
        layout.minimumLineSpacing = 12
        layout.sectionInset = NSEdgeInsets(top: FontCollection.inset, left: FontCollection.inset,
                                           bottom: FontCollection.inset, right: FontCollection.inset)

        let collectionView = FontCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.register(FontItem.self, forItemWithIdentifier: FontItem.identifier)
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.isSelectable = true
        collectionView.allowsEmptySelection = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.onCancel = { [weak coordinator = context.coordinator] in
            coordinator?.report(selection: [])
        }
        collectionView.onDoubleClick = { [window] in
            guard window.detailsHidden else { return }
            WindowState.withoutAnimation {
                window.detailsHidden = false
            }
        }

        let scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        context.coordinator.collectionView = collectionView
        context.coordinator.observeModel()
        // SwiftUI can build this view in the middle of a change to the model, when the new
        // value isn't readable yet and the change has already been announced. Look again
        // once that change has landed.
        DispatchQueue.main.async { [coordinator = context.coordinator] in
            coordinator.observeModel()
        }
        return scrollView
    }

    /// Nothing to do here: the coordinator watches the model itself, so the grid changes
    /// only when the fonts, the selection or the activity do, whatever else is redrawn.
    func updateNSView(_ scrollView: NSScrollView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        private let model: GalleryModel
        private let window: WindowState
        weak var collectionView: NSCollectionView?
        private var fonts: [FontCask] = []
        private var version = -1
        private var scrollResetKey: String?
        /// The selection as last set by a click or key press in the collection view.
        private var selectionFromHere: Set<FontCask.ID> = []
        private var watch = 0

        init(_ parent: FontCollection) {
            model = parent.model
            window = parent.window
        }

        /// Updates the grid now, and again each time something it shows changes in the model.
        func observeModel() {
            // Starting again replaces any earlier watch, so one change means one update.
            watch += 1
            let current = watch
            withObservationTracking {
                update()
            } onChange: { [weak self] in
                Task { @MainActor in
                    guard let self, self.watch == current else { return }
                    self.observeModel()
                }
            }
        }

        /// Passes a selection made in the grid on to the model.
        func report(selection tokens: Set<FontCask.ID>) {
            selectionFromHere = tokens
            guard model.selection != tokens else { return }
            WindowState.withoutAnimation {
                model.selection = tokens
            }
        }

        /// Passes on whatever is selected in the collection view now.
        private func reportSelection(of collectionView: NSCollectionView) {
            let fonts = fonts
            report(selection: Set(collectionView.selectionIndexPaths.lazy
                .map(\.item)
                .filter(fonts.indices.contains)
                .map { fonts[$0].token }))
        }

        /// Brings the collection view in line with the model's fonts, selection and activity.
        private func update() {
            let newVersion = model.visibleFontsVersion
            let selection = model.selection
            let busyToken = model.activity?.token
            let newScrollResetKey = "\(model.section)"
            guard let collectionView else { return }

            if version != newVersion {
                let old = fonts
                fonts = model.visibleFonts
                let isFirstLoad = version == -1
                version = newVersion
                let sameList = old.count == fonts.count && zip(old, fonts).allSatisfy { $0.token == $1.token }
                if sameList {
                    // The same fonts, one or two of them changed: an install finished, say.
                    let changed = zip(old, fonts).enumerated()
                        .filter { $0.element.0 != $0.element.1 }
                        .map { IndexPath(item: $0.offset, section: 0) }
                    if !changed.isEmpty {
                        collectionView.reloadItems(at: Set(changed))
                    }
                } else {
                    collectionView.reloadData()
                    collectionView.layoutSubtreeIfNeeded()
                    // A different list of fonts starts again from the top.
                    if !isFirstLoad {
                        scrollToTop(collectionView)
                    }
                }
            }
            if scrollResetKey != newScrollResetKey {
                if scrollResetKey != nil {
                    scrollToTop(collectionView)
                }
                scrollResetKey = newScrollResetKey
            }

            select(selection, in: collectionView)
            // A selection that didn't come from a click here, such as the font restored from
            // last time, is brought into view.
            if selection != selectionFromHere {
                selectionFromHere = selection
                if let selected = collectionView.selectionIndexPaths.min() {
                    collectionView.layoutSubtreeIfNeeded()
                    collectionView.scrollToItems(at: [selected], scrollPosition: .centeredVertically)
                }
            }
            for case let item as FontItem in collectionView.visibleItems() {
                item.isBusy = item.token != nil && item.token == busyToken
            }
        }

        /// Scrolls to the first row, allowing for the toolbar the grid slides under.
        private func scrollToTop(_ collectionView: NSCollectionView) {
            guard let scrollView = collectionView.enclosingScrollView else { return }
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: -scrollView.contentInsets.top))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        /// Makes the collection view's selection match the model's, without telling the model.
        private func select(_ tokens: Set<FontCask.ID>, in collectionView: NSCollectionView) {
            var wanted: Set<IndexPath> = []
            if tokens.count == 1, let token = tokens.first {
                if let index = fonts.firstIndex(where: { $0.token == token }) {
                    wanted = [IndexPath(item: index, section: 0)]
                }
            } else if !tokens.isEmpty {
                for (index, font) in fonts.enumerated() where tokens.contains(font.token) {
                    wanted.insert(IndexPath(item: index, section: 0))
                }
            }
            if collectionView.selectionIndexPaths != wanted {
                collectionView.selectionIndexPaths = wanted
            }
        }

        // MARK: Data source

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            fonts.count
        }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: FontItem.identifier, for: indexPath)
            if let item = item as? FontItem, fonts.indices.contains(indexPath.item) {
                let font = fonts[indexPath.item]
                item.configure(with: font, isBusy: font.token == model.activity?.token)
            }
            return item
        }

        // MARK: Delegate

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            reportSelection(of: collectionView)
        }

        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
            // Moving from one font to another deselects the first before selecting the second.
            // Wait to see what ends up selected before reporting it.
            DispatchQueue.main.async { [weak self, weak collectionView] in
                guard let self, let collectionView else { return }
                self.reportSelection(of: collectionView)
            }
        }
    }
}

/// A collection view that clears its selection when Escape is pressed, and says when a
/// card is double-clicked.
private final class FontCollectionView: NSCollectionView {
    var onCancel: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // A plain double-click on a card, not one that is adding to the selection.
        guard event.clickCount == 2, event.modifierFlags.isDisjoint(with: [.command, .shift]),
              indexPathForItem(at: convert(event.locationInWindow, from: nil)) != nil else { return }
        onDoubleClick?()
    }

    override func cancelOperation(_ sender: Any?) {
        deselectAll(nil)
        onCancel?()
    }
}

/// One card of the grid: a picture of "Aa" set in the font, its number of styles, and its name.
private final class FontItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("FontItem")

    private(set) var token: String?
    private var loading: Task<Void, Never>?
    private var cardView: FontCardView { view as! FontCardView }

    override func loadView() {
        view = FontCardView(frame: NSRect(origin: .zero, size: FontCollection.itemSize))
    }

    override var isSelected: Bool {
        didSet { cardView.isSelected = isSelected }
    }

    var isBusy = false {
        didSet {
            if isBusy != oldValue { cardView.isBusy = isBusy }
        }
    }

    func configure(with font: FontCask, isBusy: Bool) {
        loading?.cancel()
        token = font.token
        self.isBusy = isBusy
        cardView.show(font)

        // A picture already in memory shows at once.
        if let cached = FontThumbnails.cachedThumbnail(for: font) {
            cardView.thumbnail = .picture(cached)
            return
        }
        cardView.thumbnail = .waiting
        loading = Task { [weak self] in
            // Wait a moment before reading or downloading anything. A card that scrolls
            // straight past is reused by then, and this task cancelled, so it loads nothing.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let loaded = await FontThumbnails.shared.thumbnail(for: font)
            guard !Task.isCancelled, let self, self.token == font.token else { return }
            self.cardView.thumbnail = loaded.map(FontCardView.Thumbnail.picture) ?? .unavailable
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loading?.cancel()
        loading = nil
        token = nil
        isBusy = false
        cardView.thumbnail = .waiting
    }
}

/// The view for one card, laid out by hand: every card is the same size, so there is nothing to measure.
private final class FontCardView: NSView {
    enum Thumbnail {
        /// On screen, but not yet long enough to be worth loading.
        case waiting
        case picture(NSImage)
        /// The font can only be seen after it is installed.
        case unavailable
    }

    private let card = CardBackgroundView()
    private let picture = NSImageView()
    private let styles = NSTextField(labelWithString: "")
    private let name = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()

    private static let side = FontCollection.cardSide
    private static let placeholder: NSImage? = {
        let configuration = NSImage.SymbolConfiguration(pointSize: side * 0.18, weight: .regular)
        return NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }()
    private static let installedMark: NSAttributedString = {
        let attachment = NSTextAttachment()
        let configuration = NSImage.SymbolConfiguration(paletteColors: [.systemGreen])
        attachment.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Installed")?
            .withSymbolConfiguration(configuration)
        let mark = NSMutableAttributedString(string: " ")
        mark.append(NSAttributedString(attachment: attachment))
        return mark
    }()

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        let side = Self.side

        card.frame = NSRect(x: 0, y: 0, width: side, height: side)
        addSubview(card)

        picture.frame = NSRect(x: 0, y: 0, width: side, height: side * 0.76)
        picture.imageScaling = .scaleNone
        picture.imageAlignment = .alignCenter
        addSubview(picture)

        styles.frame = NSRect(x: 4, y: side * 0.76, width: side - 8, height: side * 0.24)
        styles.font = .preferredFont(forTextStyle: .footnote)
        styles.textColor = .secondaryLabelColor
        styles.alignment = .center
        styles.lineBreakMode = .byTruncatingTail
        addSubview(styles)

        name.frame = NSRect(x: 0, y: side + 8, width: side, height: 32)
        name.font = .preferredFont(forTextStyle: .callout)
        name.alignment = .center
        name.maximumNumberOfLines = 2
        name.cell?.truncatesLastVisibleLine = true
        addSubview(name)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.frame = NSRect(x: side - 24, y: 8, width: 16, height: 16)
        addSubview(spinner)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isSelected = false {
        didSet { card.isSelected = isSelected }
    }

    var isBusy = false {
        didSet {
            if isBusy {
                spinner.startAnimation(nil)
            } else {
                spinner.stopAnimation(nil)
            }
        }
    }

    var thumbnail = Thumbnail.waiting {
        didSet {
            switch thumbnail {
            case .waiting:
                picture.image = nil
            case .picture(let image):
                picture.image = image
                picture.contentTintColor = .labelColor
            case .unavailable:
                picture.image = Self.placeholder
                picture.contentTintColor = .tertiaryLabelColor
            }
        }
    }

    func show(_ font: FontCask) {
        switch font.fontFiles.count {
        case 0: styles.stringValue = ""
        case 1: styles.stringValue = "1 style"
        default: styles.stringValue = "\(font.fontFiles.count) styles"
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let title = NSMutableAttributedString(string: font.name, attributes: [
            .font: NSFont.preferredFont(forTextStyle: .callout),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ])
        if font.isInstalled {
            title.append(Self.installedMark)
            title.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: title.length))
        }
        name.attributedStringValue = title
        setAccessibilityLabel(font.isInstalled ? "\(font.name), installed" : font.name)
    }
}

/// The white card itself: a rounded rectangle with a hairline border and a soft shadow,
/// or the accent colour's border when its font is selected.
private final class CardBackgroundView: NSView {
    var isSelected = false {
        didSet {
            if isSelected != oldValue { needsDisplay = true }
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    /// Called again whenever the appearance changes, so the colours follow light and dark mode.
    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        layer.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer.borderWidth = isSelected ? 3 : 1
        layer.borderColor = (isSelected ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer.shadowColor = NSColor.shadowColor.cgColor
        layer.shadowOpacity = 0.1
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: -1)
        layer.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 10, cornerHeight: 10, transform: nil)
        layer.masksToBounds = false
    }
}
