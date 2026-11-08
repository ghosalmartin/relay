import AppKit

/// Brings the app forward from outside SwiftUI, such as when an alert is clicked.
@MainActor
final class MainWindowOpener {
    static let windowID = "main"

    var open: (() -> Void)?

    func bringToFront() {
        NSApp.activate()
        if !NSApp.windows.contains(where: \.isVisible) {
            open?()
        }
    }
}
