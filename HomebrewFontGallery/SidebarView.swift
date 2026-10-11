import SwiftUI

/// The sidebar: every font, the installed and not-installed ones, and the categories.
///
/// It is a view of its own so that it is redrawn only when the counts or the chosen row
/// change, and not with the rest of the window.
struct SidebarView: View {
    @Bindable var model: GalleryModel

    var body: some View {
        List(selection: selection) {
            row("All Fonts", systemImage: "square.grid.2x2", count: model.fonts.count)
                .tag(GalleryModel.Section.all)
            row("Installed", systemImage: "checkmark.circle", count: model.installedCount)
                .tag(GalleryModel.Section.installed)
            row("Not Installed", systemImage: "arrow.down.circle", count: model.fonts.count - model.installedCount)
                .tag(GalleryModel.Section.notInstalled)
            if !model.categories.isEmpty {
                Section("Categories") {
                    ForEach(model.categories) { category in
                        row(category.word, systemImage: category.symbolName, count: category.count)
                            .tag(GalleryModel.Section.category(category.id))
                    }
                }
            }
        }
    }

    /// A row is always chosen: clicking empty space leaves the current one.
    private var selection: Binding<GalleryModel.Section?> {
        Binding(
            get: { model.section },
            set: { if let section = $0 { model.section = section } }
        )
    }

    /// Every icon is drawn to fit the same square, so wide symbols and narrow ones take up
    /// the same room and the titles line up.
    private static let iconSide: CGFloat = 16

    private func row(_ title: String, systemImage: String, count: Int) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .resizable()
                .scaledToFit()
                .frame(width: Self.iconSide, height: Self.iconSide)
        }
        .badge(model.loadState == .loaded ? Text(count.formatted()) : nil)
    }
}
