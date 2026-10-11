import SwiftUI

/// One cell of the grid: "Aa" set in the font, with the font's name below.
struct FontThumbnailView: View {
    let font: FontCask
    let isSelected: Bool
    let isBusy: Bool

    @State private var face: FontFace?
    @State private var isLoading = true

    private static let sample = "Aa"
    private static let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    private struct Key: Equatable {
        let token: String
        let installedVersion: String?
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Self.shape.fill(.fill.quaternary)
                if let face {
                    Text(Self.sample)
                        .font(Font(face.font(size: 56)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .padding(.horizontal, 12)
                } else if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "eye.slash")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                        .help("Install this font to preview it.")
                }
            }
            .frame(height: 120)
            .clipShape(Self.shape)
            .overlay {
                if isSelected {
                    Self.shape.strokeBorder(Color.accentColor, lineWidth: 3)
                }
            }

            HStack(spacing: 4) {
                Text(font.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
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
        }
        .contentShape(Rectangle())
        .task(id: Key(token: font.token, installedVersion: font.installedVersion)) {
            let loaded = await FontThumbnails.shared.face(for: font)
            guard !Task.isCancelled else { return }
            face = loaded
            isLoading = false
        }
    }
}
