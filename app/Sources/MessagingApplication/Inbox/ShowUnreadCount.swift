import MessagingDomain

/// Keeps the badge in step with how many conversations are unread, for as long as it runs.
public struct ShowUnreadCount: Sendable {
    private let observeInbox: ObserveInbox
    private let badge: any UnreadBadge

    public init(observeInbox: ObserveInbox, badge: any UnreadBadge) {
        self.observeInbox = observeInbox
        self.badge = badge
    }

    public func callAsFunction() async {
        for await snapshot in observeInbox() {
            await badge.show(Self.label(for: snapshot.conversations))
        }
    }

    static func label(for conversations: [Conversation]) -> String? {
        let unread = conversations.filter(\.isUnread).count
        return unread > 0 ? String(unread) : nil
    }
}
