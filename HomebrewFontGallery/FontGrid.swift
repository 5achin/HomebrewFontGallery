import SwiftUI

/// The scrolling grid of font cards, and what it shows when there are none.
///
/// It is its own view, holding only references, so that changes elsewhere in the window,
/// such as showing or hiding the details pane, leave it alone.
struct FontGrid: View {
    let model: GalleryModel
    let window: WindowState

    var body: some View {
        FontCollection(model: model, window: window)
        .overlay {
            if model.visibleFonts.isEmpty {
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
