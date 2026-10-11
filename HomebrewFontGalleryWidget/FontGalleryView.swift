import AppIntents
import SwiftUI
import WidgetKit

struct FontGalleryView: View {
    let entry: FontGalleryEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let font = font(entry.fonts.text, offset: 0) {
            switch family {
            case .systemSmall:
                SmallSample(font: font, size: family.sizeName)
            case .systemMedium:
                TextSample(text: Samples.pangram, font: font, pointSize: 28, size: family.sizeName)
            case .systemExtraLarge:
                DocumentSample(heading: font,
                               paragraph: self.font(entry.fonts.text, offset: 1) ?? font,
                               code: self.font(entry.fonts.code, offset: 0),
                               size: family.sizeName)
            default:
                TextSample(text: Samples.loremIpsum, font: font, pointSize: 16, size: family.sizeName)
            }
        } else {
            NoFontsView()
        }
    }

    /// The font the buttons have reached in a list, or the one a few places after it.
    private func font(_ fonts: [CachedFont], offset: Int) -> CachedFont? {
        guard !fonts.isEmpty else { return nil }
        return fonts[DailyFonts.position(entry.presses + offset, count: fonts.count)]
    }
}

enum Samples {
    static let pangram = "The quick brown fox jumps over the lazy dog."
    static let loremIpsum = """
        Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et \
        dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip \
        ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu \
        fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia \
        deserunt mollit anim id est laborum.
        """
    static let heading = "The Shape of Words"
    static let paragraph = """
        A typeface sets the voice of a page before a single word is read. Good type goes unnoticed: it carries \
        the reader along, line after line, without once asking for attention.
        """
    static let list = ["Headings draw the eye.", "Paragraphs carry the story.", "Code keeps every column aligned."]
    static let code = """
        struct Sample {
            let name: String
            var size = 12.0
        }

        for sample in gallery {
            print(sample.name)
        }
        """
}

private extension CachedFont {
    func font(_ size: CGFloat) -> Font {
        .custom(postScriptName, fixedSize: size)
    }
}

/// The font's name with the back and forward buttons, along the bottom of every size.
private struct Footer: View {
    let title: String
    let size: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(intent: RotateFontIntent(size: size, step: -1)) {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous Font")
            Button(intent: RotateFontIntent(size: size, step: 1)) {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next Font")
        }
        .buttonBorderShape(.circle)
        .controlSize(.small)
    }
}

private struct SmallSample: View {
    let font: CachedFont
    let size: String

    var body: some View {
        VStack(spacing: 4) {
            Text("Aa")
                .font(font.font(64))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Footer(title: font.name, size: size)
        }
    }
}

private struct TextSample: View {
    let text: String
    let font: CachedFont
    let pointSize: CGFloat
    let size: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(font.font(pointSize))
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Footer(title: font.name, size: size)
        }
    }
}

/// A page with a heading, a paragraph, a list and some code, each in its own font.
private struct DocumentSample: View {
    let heading: CachedFont
    let paragraph: CachedFont
    let code: CachedFont?
    let size: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(Samples.heading)
                        .font(heading.font(30))
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    Text(Samples.paragraph)
                        .font(paragraph.font(15))
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(Samples.list.enumerated()), id: \.offset) { index, item in
                            Text("\(index + 1). \(item)")
                        }
                    }
                    .font(paragraph.font(15))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Text(Samples.code)
                    .font(code?.font(13) ?? .system(size: 13, design: .monospaced))
                    .minimumScaleFactor(0.7)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .minimumScaleFactor(0.7)
            Footer(title: title, size: size)
        }
    }

    private var title: String {
        var parts = ["Heading: \(heading.name)", "Text: \(paragraph.name)"]
        if let code {
            parts.append("Code: \(code.name)")
        }
        return parts.joined(separator: "  ·  ")
    }
}

private struct NoFontsView: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "textformat")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("No Fonts Yet")
                .font(.headline)
            Text("Today’s fonts appear once your Mac is online.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
