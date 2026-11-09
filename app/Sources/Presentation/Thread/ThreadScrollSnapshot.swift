/// Where the message list is, reduced to what decides whether it should stay on the newest message.
public struct ThreadScrollSnapshot: Equatable, Sendable {
    /// Room for rubber-banding and rounding, so being almost at the end still counts.
    static let tolerance = 40.0

    public let contentHeight: Double
    public let visibleBottom: Double

    public init(contentHeight: Double, visibleBottom: Double) {
        self.contentHeight = contentHeight
        self.visibleBottom = visibleBottom
    }

    /// Pictures and late messages change the height after the chat opens. Someone reading further up stays put.
    public func shouldFollow(to next: ThreadScrollSnapshot) -> Bool {
        contentHeight - visibleBottom <= Self.tolerance && next.contentHeight != contentHeight
    }
}
