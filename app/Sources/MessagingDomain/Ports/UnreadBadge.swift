/// A count shown outside the app's window, such as on the Dock icon.
public protocol UnreadBadge: Sendable {
    /// Nil clears it.
    func show(_ label: String?) async
}
