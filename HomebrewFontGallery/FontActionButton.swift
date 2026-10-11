import SwiftUI

/// The button above the details pane, or in the toolbar when the pane is hidden: green
/// Install, or red Uninstall. With several fonts selected it acts on all of them.
///
/// While Homebrew works it shows a spinner in place of its icon, and clicking it offers to
/// stop. When an install finishes it fades from green to red and becomes Uninstall.
struct FontActionButton: View {
    let model: GalleryModel
    let window: WindowState
    /// Set above the details pane, where the button is one width whatever its title. The
    /// width goes on the label, inside the button, so the highlight under the pointer
    /// covers all of the button and not just its title.
    var width: CGFloat?

    @State private var isHovered = false

    var body: some View {
        let activity = model.activity
        let action = model.selectionAction
        // The colour says what the button will do, or is doing.
        let removes = activity.map { $0.kind == .uninstalling } ?? (action?.kind == .uninstall)

        Button {
            if activity != nil {
                window.confirmingCancel = true
            } else if let action, action.kind == .uninstall {
                window.confirmingUninstall = action.fonts
            } else if let action {
                model.install(action.fonts)
            }
        } label: {
            Label {
                Text(title(activity: activity, action: action))
            } icon: {
                if activity != nil {
                    ProgressView()
                        .controlSize(.small)
                        // A light spinner, to show on the button's colour.
                        .colorScheme(.dark)
                } else {
                    Image(systemName: removes ? "trash" : "arrow.down.circle")
                }
            }
            .frame(width: width.map { $0 - Self.padding })
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderedProminent)
        .tint(removes ? .red : .green)
        .animation(.easeInOut(duration: 0.6), value: removes)
        .keyboardShortcut(removes || activity != nil ? nil : .defaultAction)
        // A wash of white under the pointer, so the button lightens instead of darkening.
        .overlay {
            Capsule()
                .fill(.white.opacity(isHovered && !isDisabled(activity: activity, action: action) ? 0.25 : 0))
                .allowsHitTesting(false)
        }
        .onHover { isHovered = $0 }
        .disabled(isDisabled(activity: activity, action: action))
        .help(help(activity: activity, action: action))
    }

    /// The room the button's own shape takes up on either side of its label.
    private static let padding: CGFloat = 16

    private func isDisabled(activity: GalleryModel.Activity?, action: GalleryModel.SelectionAction?) -> Bool {
        activity?.isCancelling ?? (action?.fonts.isEmpty ?? true)
    }

    private func title(activity: GalleryModel.Activity?, action: GalleryModel.SelectionAction?) -> String {
        guard let activity else { return action?.title ?? "Install" }
        if activity.isCancelling { return "Stopping…" }
        return activity.kind == .installing ? "Installing…" : "Uninstalling…"
    }

    private func help(activity: GalleryModel.Activity?, action: GalleryModel.SelectionAction?) -> String {
        if let activity {
            let verb = activity.kind == .installing ? "Installing" : "Uninstalling"
            let progress = activity.total > 1 ? ", \(activity.position.formatted()) of \(activity.total.formatted())" : ""
            return "\(verb) “\(activity.name)”\(progress). Click to stop."
        }
        guard let action else { return "Select a font to install it." }
        guard let font = action.fonts.first else {
            let subject = action.isMultiple ? "These fonts" : "This font"
            return "\(subject) can’t be \(action.kind == .install ? "installed" : "uninstalled") here."
        }
        if action.fonts.count == 1 {
            return action.kind == .install ? "Install “\(font.name)” on this Mac." : "Remove “\(font.name)” from this Mac."
        }
        let count = GalleryModel.fontCount(action.fonts.count)
        return action.kind == .install
            ? "Install \(count) on this Mac, one after another."
            : "Remove \(count) from this Mac."
    }
}

/// The details pane's contents, redrawn only when the selection or what is happening to it changes.
struct DetailsPane: View {
    let model: GalleryModel

    var body: some View {
        if let font = model.selectedFont {
            FontDetailView(font: font, activity: model.activity, status: model.status)
        } else {
            SelectionSummaryView(fonts: model.selectedFonts, action: model.selectionAction,
                                 activity: model.activity, status: model.status)
        }
    }
}
