import SwiftUI

/// The button above the details pane: green Install, or red Uninstall.
///
/// While Homebrew works it shows a spinner in place of its icon, and clicking it offers to
/// stop. When an install finishes it fades from green to red and becomes Uninstall.
struct FontActionButton: View {
    let model: GalleryModel
    let window: WindowState

    var body: some View {
        let activity = model.activity
        let font = model.selectedFont
        // The colour says what the button will do, or is doing.
        let removes = activity.map { $0.kind == .uninstalling } ?? (font?.isInstalled == true)

        Button {
            if activity != nil {
                window.confirmingCancel = true
            } else if let font, font.isInstalled {
                window.confirmingUninstall = font
            } else if let font {
                model.install(font)
            }
        } label: {
            Label {
                Text(title(activity: activity, removes: removes))
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
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderedProminent)
        .tint(removes ? .red : .green)
        .animation(.easeInOut(duration: 0.6), value: removes)
        .keyboardShortcut(removes || activity != nil ? nil : .defaultAction)
        .disabled(isDisabled(activity: activity, font: font))
        .help(help(activity: activity, font: font))
    }

    private func title(activity: GalleryModel.Activity?, removes: Bool) -> String {
        guard let activity else { return removes ? "Uninstall" : "Install" }
        if activity.isCancelling { return "Stopping…" }
        return activity.kind == .installing ? "Installing…" : "Uninstalling…"
    }

    private func isDisabled(activity: GalleryModel.Activity?, font: FontCask?) -> Bool {
        if let activity { return activity.isCancelling }
        guard let font else { return true }
        return font.isInstalled ? font.needsInstaller : !font.isInstallable
    }

    private func help(activity: GalleryModel.Activity?, font: FontCask?) -> String {
        if let activity {
            return activity.kind == .installing
                ? "Installing “\(activity.name)”. Click to stop."
                : "Uninstalling “\(activity.name)”. Click to stop."
        }
        guard let font else { return "Select a font to install it." }
        return font.isInstalled ? "Remove “\(font.name)” from this Mac." : "Install “\(font.name)” on this Mac."
    }
}

/// The details pane's contents, redrawn only when the font or what is happening to it changes.
struct DetailsPane: View {
    let model: GalleryModel
    let font: FontCask

    var body: some View {
        FontDetailView(font: font, activity: model.activity, status: model.status)
    }
}
