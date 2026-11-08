import MessagingDomain

/// What the inbox screen needs at a point in time.
public struct InboxSnapshot: Equatable, Sendable {
    public let conversations: [Conversation]
    public let isSyncing: Bool

    public init(conversations: [Conversation], isSyncing: Bool) {
        self.conversations = conversations
        self.isSyncing = isSyncing
    }
}
