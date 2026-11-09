import MessagingDomain

/// Folds client events into the current inbox. Pure value type: no I/O, no time.
public struct InboxProjection: Equatable, Sendable {
    private let conversationsByID: [ConversationID: Conversation]
    public let hasCompletedInitialSync: Bool

    public init() {
        self.init(conversationsByID: [:], hasCompletedInitialSync: false)
    }

    private init(conversationsByID: [ConversationID: Conversation], hasCompletedInitialSync: Bool) {
        self.conversationsByID = conversationsByID
        self.hasCompletedInitialSync = hasCompletedInitialSync
    }

    /// Newest activity first, the order the inbox shows.
    public var conversations: [Conversation] {
        conversationsByID.values.sorted { $0.lastActivity > $1.lastActivity }
    }

    /// The inbox after `event`. Equal to this one if the event changed nothing.
    public func applying(_ event: MessagingEvent) -> InboxProjection {
        switch event {
        case .conversationUpdated(let conversation):
            InboxProjection(
                conversationsByID: conversationsByID.merging([conversation.id: conversation]) { _, updated in updated },
                hasCompletedInitialSync: hasCompletedInitialSync
            )
        case .conversationRemoved(let id):
            InboxProjection(conversationsByID: conversationsByID.filter { $0.key != id }, hasCompletedInitialSync: hasCompletedInitialSync)
        case .initialSyncCompleted:
            InboxProjection(conversationsByID: conversationsByID, hasCompletedInitialSync: true)
        case .loggedOut, .paired:   // a new pairing may be a different phone
            InboxProjection()
        default:
            self
        }
    }
}
