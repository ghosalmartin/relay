import MessagingDomain

/// Folds client events into the current inbox. Pure value type: no I/O, no time.
public struct InboxProjection: Equatable, Sendable {
    private var conversationsByID: [ConversationID: Conversation] = [:]
    public private(set) var hasCompletedInitialSync = false

    public init() {}

    /// Newest activity first, the order the inbox shows.
    public var conversations: [Conversation] {
        conversationsByID.values.sorted { $0.lastActivity > $1.lastActivity }
    }

    /// Applies one event. Returns true when the inbox changed.
    public mutating func apply(_ event: MessagingEvent) -> Bool {
        switch event {
        case .conversationUpdated(let conversation):
            return upsert(conversation)
        case .initialSyncCompleted:
            guard !hasCompletedInitialSync else { return false }
            hasCompletedInitialSync = true
            return true
        case .loggedOut:
            self = InboxProjection()
            return true
        default:
            return false
        }
    }

    private mutating func upsert(_ conversation: Conversation) -> Bool {
        guard conversationsByID[conversation.id] != conversation else { return false }
        conversationsByID[conversation.id] = conversation
        return true
    }
}
