import MessagingDomain

/// Fetches a page of a thread's history, oldest message first.
public struct LoadThreadHistory: Sendable {
    public static let pageSize = 30

    private let client: any MessagingClient

    public init(client: any MessagingClient) {
        self.client = client
    }

    /// - Parameter cursor: nil for the latest page; a page's `olderCursor` for the one before it.
    public func callAsFunction(_ conversation: ConversationID, before cursor: HistoryCursor? = nil) async throws(MessagingError) -> MessagePage {
        try await client.messages(in: conversation, before: cursor, limit: Self.pageSize)
    }
}
