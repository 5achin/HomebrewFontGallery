import SwiftUI
import WidgetKit

struct FontGalleryEntry: TimelineEntry {
    let date: Date
    let fonts: CachedDay
    /// How often forward has been pressed, less the presses of back, on this size of widget.
    let presses: Int
}

struct FontGalleryProvider: TimelineProvider {
    func placeholder(in context: Context) -> FontGalleryEntry {
        FontGalleryEntry(date: .now, fonts: .empty, presses: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (FontGalleryEntry) -> Void) {
        Task { completion(await entry(for: context.family)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FontGalleryEntry>) -> Void) {
        Task {
            let entry = await entry(for: context.family)
            // Without fonts, most likely because the Mac is offline, try again before long.
            let next = entry.fonts.text.isEmpty ? Date.now.addingTimeInterval(15 * 60) : DailyFonts.nextDay(after: .now)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func entry(for family: WidgetFamily) async -> FontGalleryEntry {
        let now = Date.now
        let fonts = await DailyFontCache.fonts(for: DailyFonts.day(for: now))
        let folder = DailyFontCache.folder(for: fonts.day)
        for font in fonts.text + fonts.code {
            FontFiles.register(folder.appendingPathComponent(font.file))
        }
        return FontGalleryEntry(date: now, fonts: fonts, presses: WidgetPosition.presses(for: family.sizeName))
    }
}

extension WidgetFamily {
    /// The name the back and forward buttons count their presses under.
    var sizeName: String {
        switch self {
        case .systemSmall: "small"
        case .systemMedium: "medium"
        case .systemLarge: "large"
        case .systemExtraLarge: "extraLarge"
        default: "other"
        }
    }
}

@main
struct FontGalleryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FontGallery", provider: FontGalleryProvider()) { entry in
            FontGalleryView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Font Gallery")
        .description("A new set of Homebrew’s fonts every day.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}
