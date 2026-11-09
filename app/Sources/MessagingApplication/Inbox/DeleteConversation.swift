import MessagingDomain

/// Deletes a whole conversation from the phone.
public struct DeleteConversation: Sendable {
    private let client: any MessagingClient

    public init(client: any MessagingClient) {
        self.client = client
    }

    public func callAsFunction(_ conversation: ConversationID) async throws(MessagingError) {
        try await client.delete(conversation)
    }
}
