import SwiftUI

/// One cell of the grid: a picture of "Aa" set in the font, with the font's name below.
struct FontThumbnailView: View {
    let font: FontCask
    let isSelected: Bool
    let isBusy: Bool

    @State private var thumbnail: NSImage?
    @State private var state = LoadState.waiting

    private enum LoadState {
        /// On screen, but not yet long enough to be worth loading.
        case waiting
        case loading
        case loaded
    }

    private static let sample = "Aa"
    private static let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    /// The card is one size everywhere, so its parts are laid out with plain numbers.
    /// Measuring each card as the window resized made resizing choppy.
    static let side: CGFloat = 116

    /// A white card with the sample in the middle and the number of styles along the bottom.
    private var card: some View {
        VStack(spacing: 0) {
            ZStack {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .renderingMode(.template)
                        .foregroundStyle(.primary)
                        .accessibilityHidden(true)
                } else if state == .loading {
                    ProgressView()
                        .controlSize(.small)
                } else if state == .loaded {
                    Image(systemName: "eye.slash")
                        .font(.system(size: Self.side * 0.18))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: Self.side, height: Self.side * 0.76)

            Text(styleCount ?? "")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: Self.side, height: Self.side * 0.24, alignment: .top)
        }
        .frame(width: Self.side, height: Self.side)
        // The shadow belongs to the plain card behind, which is cheaper to draw than
        // a shadow of everything on it.
        .background {
            Self.shape
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color(nsColor: .shadowColor).opacity(0.1), radius: 3, y: 1)
        }
        .overlay {
            if isSelected {
                Self.shape.strokeBorder(Color.accentColor, lineWidth: 3)
            } else {
                Self.shape.strokeBorder(.separator)
            }
        }
    }

    private var styleCount: String? {
        switch font.fontFiles.count {
        case 0: return nil
        case 1: return "1 style"
        default: return "\(font.fontFiles.count) styles"
        }
    }

    private struct Key: Equatable {
        let token: String
        let installedVersion: String?
    }

    var body: some View {
        VStack(spacing: 8) {
            card

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(font.name)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                } else if font.isInstalled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("Installed")
                }
            }
            .padding(.horizontal, 4)
            // Room for two lines, so every row of cards lines up.
            .frame(minHeight: 32, alignment: .top)
        }
        .contentShape(Rectangle())
        .task(id: Key(token: font.token, installedVersion: font.installedVersion)) {
            // A picture already in memory shows at once.
            if let cached = FontThumbnails.cachedThumbnail(for: font) {
                thumbnail = cached
                state = .loaded
                return
            }
            thumbnail = nil
            state = .waiting
            // Wait a moment before reading or downloading anything. A card that scrolls
            // straight past is gone by then, and this task with it, so it loads nothing.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            state = .loading
            let loaded = await FontThumbnails.shared.thumbnail(for: font)
            guard !Task.isCancelled else { return }
            thumbnail = loaded
            state = .loaded
        }
    }
}
