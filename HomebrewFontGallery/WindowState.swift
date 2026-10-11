import Observation
import SwiftUI

/// What the window is showing, shared by the toolbar, the grid and the details pane.
/// It is a class so that views can hold it without being redrawn when the parts they
/// don't read change.
@MainActor
@Observable
final class WindowState {
    /// True when the user has hidden the details pane.
    var detailsHidden = false
    /// The font whose uninstall is waiting to be confirmed.
    var confirmingUninstall: FontCask?
    /// True while stopping the current install or uninstall is waiting to be confirmed.
    var confirmingCancel = false

    /// Makes a change that shows or hides the details pane without sliding it.
    static func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }
}
