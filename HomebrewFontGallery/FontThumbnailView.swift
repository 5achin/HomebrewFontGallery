import SwiftUI

/// One cell of the grid: a picture of "Aa" set in the font, with the font's name below.
struct FontThumbnailView: View {
    let font: FontCask
    let isSelected: Bool
    let isBusy: Bool

    @State private var thumbnail: NSImage?
    @State private var isLoading = true

    private static let sample = "Aa"
    private static let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    /// A white card with the sample in the middle and the number of styles along the bottom.
    private var card: some View {
        GeometryReader { geometry in
            let side = geometry.size.width
            // The saved thumbnail is drawn for a card of the grid's own width.
            ZStack {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .renderingMode(.template)
                        .foregroundStyle(.primary)
                        .accessibilityHidden(true)
                } else if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "eye.slash")
                        .font(.system(size: side * 0.18))
                        .foregroundStyle(.tertiary)
                        .help("Install this font to preview it.")
                }
            }
            .frame(width: side, height: side * 0.8)

            if let styleCount {
                Text(styleCount)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: side, height: side * 0.2, alignment: .top)
                    .offset(y: side * 0.76)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: Self.shape)
        .clipShape(Self.shape)
        .overlay {
            if isSelected {
                Self.shape.strokeBorder(Color.accentColor, lineWidth: 3)
            } else {
                Self.shape.strokeBorder(.separator)
            }
        }
        .shadow(color: Color(nsColor: .shadowColor).opacity(0.1), radius: 3, y: 1)
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
        VStack(spacing: 10) {
            card
                .aspectRatio(1, contentMode: .fit)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(font.name)
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
            .frame(minHeight: 34, alignment: .top)
        }
        .contentShape(Rectangle())
        .task(id: Key(token: font.token, installedVersion: font.installedVersion)) {
            let loaded = await FontThumbnails.shared.thumbnail(for: font)
            guard !Task.isCancelled else { return }
            thumbnail = loaded
            isLoading = false
        }
    }
}
