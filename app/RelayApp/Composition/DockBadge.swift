import AppKit
import MessagingDomain

/// The count on Relay's Dock icon.
struct DockBadge: UnreadBadge {
    func show(_ label: String?) async {
        await MainActor.run { NSApplication.shared.dockTile.badgeLabel = label }
    }
}
