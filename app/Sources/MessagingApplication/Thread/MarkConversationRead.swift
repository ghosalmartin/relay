import MessagingDomain

/// Tells the phone the user has read a conversation up to its latest message.
public struct MarkConversationRead: Sendable {
    private let client: any MessagingClient

    public init(client: any MessagingClient) {
        self.client = client
    }

    public func callAsFunction(_ conversation: ConversationID, upTo message: MessageID) async throws(MessagingError) {
        try await client.markRead(conversation, upTo: message)
    }
}
