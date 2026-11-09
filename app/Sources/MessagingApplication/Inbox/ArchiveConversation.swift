import MessagingDomain

/// Moves a conversation out of the inbox into the phone's archive.
public struct ArchiveConversation: Sendable {
    private let client: any MessagingClient

    public init(client: any MessagingClient) {
        self.client = client
    }

    public func callAsFunction(_ conversation: ConversationID) async throws(MessagingError) {
        try await client.archive(conversation)
    }
}
