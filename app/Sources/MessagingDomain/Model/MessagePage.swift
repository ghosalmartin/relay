/// One page of thread history, oldest first, plus where to continue from.
public struct MessagePage: Sendable, Equatable {
    public let messages: [Message]
    /// Pass back to fetch older messages. Nil when there is no more history.
    public let olderCursor: HistoryCursor?

    public init(messages: [Message], olderCursor: HistoryCursor?) {
        self.messages = messages
        self.olderCursor = olderCursor
    }
}

/// Opaque position in a thread's history. Only the client that issued it understands it.
public struct HistoryCursor: Hashable, Sendable {
    public let token: String
    public init(token: String) { self.token = token }
}
