import AppKit

/// Brings the app forward from outside SwiftUI, such as when an alert is clicked.
@MainActor
final class MainWindowOpener {
    static let windowID = "main"

    var open: (() -> Void)?

    func bringToFront() {
        NSApp.activate()
        // Not just any visible window: the hidden website has one too.
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
            open?()
        }
    }
}
