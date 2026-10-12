import AppIntents
import AppKit
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
                    .widgetURL(FontLink.url(for: font.token))
            case .systemMedium:
                TextSample(text: Samples.pangram, font: font, pointSize: 28, size: family.sizeName)
                    .widgetURL(FontLink.url(for: font.token))
            case .systemExtraLarge:
                document(fallback: font)
            default:
                TextSample(text: Samples.loremIpsum, font: font, pointSize: 16, size: family.sizeName)
                    .widgetURL(FontLink.url(for: font.token))
            }
        } else {
            NoFontsView()
        }
    }

    /// The combination the buttons have reached, or one font throughout on a day that has none.
    private func document(fallback: CachedFont) -> DocumentSample {
        let fonts = entry.fonts
        guard !fonts.combinations.isEmpty else {
            return DocumentSample(heading: fallback, paragraph: fallback, code: fonts.code.first, size: family.sizeName)
        }
        let combination = fonts.combinations[DailyFonts.position(entry.presses, count: fonts.combinations.count)]
        return DocumentSample(heading: fonts.font(combination.heading) ?? fallback,
                              paragraph: fonts.font(combination.paragraph) ?? fallback,
                              code: fonts.font(combination.code), size: family.sizeName)
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
        import Typography

        // One font in today's gallery.
        struct Sample {
            let name: String
            var size = 12.0
            var isMonospaced = false
        }

        func label(_ sample: Sample) -> String {
            if sample.isMonospaced {
                return "\\(sample.name), code"
            }
            return "\\(sample.name), text"
        }

        for sample in gallery.prefix(8) {
            print(label(sample))
        }
        """
}

private extension CachedFont {
    func font(_ size: CGFloat) -> Font {
        .custom(postScriptName, fixedSize: size)
    }
}

/// The font's name, along the top of every size.
private struct FontTitle: View {
    let title: String
    /// The small widget is narrow, so its title may take two lines.
    var lines = 1

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(lines)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The back and forward buttons, in the bottom corner of every size: one capsule
/// holding both arrows, as the back and forward buttons of a toolbar are.
private struct Arrows: View {
    let size: String

    var body: some View {
        HStack(spacing: 0) {
            arrow("chevron.left", step: -1, label: "Previous Font")
            Divider()
                .frame(height: 14)
            arrow("chevron.right", step: 1, label: "Next Font")
        }
        .glassSurface(Capsule())
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func arrow(_ symbol: String, step: Int, label: String) -> some View {
        Button(intent: RotateFontIntent(size: size, step: step)) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private extension View {
    func glassPanel(cornerRadius: CGFloat) -> some View {
        glassSurface(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func glassSurface(_ shape: some InsettableShape) -> some View {
        modifier(GlassSurface(shape: shape))
    }
}

/// A frosted surface behind a view, with a hairline that catches the light along its top edge.
/// The system's own glass effect and glass buttons draw nothing inside a widget, so
/// this is built from a material.
private struct GlassSurface<Surface: InsettableShape>: ViewModifier {
    let shape: Surface
    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        let highlight = LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom)
        if renderingMode == .fullColor {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(highlight, lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        } else {
            // With the Clear or Tinted widget style the system draws the widget as glass and
            // paints every solid shape in one colour, so a surface has to stay faint to leave
            // what is on it readable.
            content
                .background(.white.opacity(0.12), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.25), lineWidth: 1))
        }
    }
}

private struct SmallSample: View {
    let font: CachedFont
    let size: String

    var body: some View {
        VStack(spacing: 2) {
            FontTitle(title: font.name, lines: 2)
            Text("Aa")
                .font(font.font(60))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Arrows(size: size)
        }
    }
}

private struct TextSample: View {
    let text: String
    let font: CachedFont
    let pointSize: CGFloat
    let size: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FontTitle(title: font.name)
            Text(text)
                .font(font.font(pointSize))
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Arrows(size: size)
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
            FontTitle(title: title)
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    linked(to: heading) {
                        Text(Samples.heading)
                            .font(heading.font(30))
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                    }
                    linked(to: paragraph) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(Samples.paragraph)
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(Samples.list.enumerated()), id: \.offset) { index, item in
                                    Text("\(index + 1). \(item)")
                                }
                            }
                        }
                        .font(paragraph.font(15))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                linked(to: code) {
                    HighlightedCode(code: Samples.code)
                        .font(code?.font(12) ?? .system(size: 12, design: .monospaced))
                        .minimumScaleFactor(0.7)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .glassPanel(cornerRadius: 12)
                }
            }
            .minimumScaleFactor(0.7)
            Arrows(size: size)
        }
        // A click outside the three samples opens the heading's font.
        .widgetURL(FontLink.url(for: heading.token))
    }

    /// Makes a sample open its own font in the app when clicked.
    @ViewBuilder
    private func linked(to font: CachedFont?, @ViewBuilder content: () -> some View) -> some View {
        if let font, let url = FontLink.url(for: font.token) {
            Link(destination: url, label: content)
                .buttonStyle(.plain)
        } else {
            content()
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

/// Code with its keywords, types, strings, numbers and comments in the system's colours.
private struct HighlightedCode: View {
    let code: String

    var body: some View {
        CodeTokens.tokens(in: code).reduce(Text("")) { text, token in
            text + Text(token.text).foregroundStyle(color(for: token.kind))
        }
    }

    private func color(for kind: CodeTokens.Kind) -> Color {
        switch kind {
        case .plain: .primary
        case .keyword: .pink
        case .type: .teal
        case .string: .red
        case .number: .purple
        // The label colour itself: over a material, the secondary style is drawn at full strength.
        case .comment: Color(nsColor: .secondaryLabelColor)
        }
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
