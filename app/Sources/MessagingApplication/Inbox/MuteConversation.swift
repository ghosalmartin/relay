import MessagingDomain

/// Turns a conversation's notifications on the phone off or on.
public struct MuteConversation: Sendable {
    private let client: any MessagingClient

    public init(client: any MessagingClient) {
        self.client = client
    }

    public func callAsFunction(_ conversation: ConversationID, isMuted: Bool) async throws(MessagingError) {
        try await client.setMuted(isMuted, conversation)
    }
}
