import MessagingDomain

/// Puts an emoji on a message.
public struct SendReaction: Sendable {
    private let client: any MessagingClient

    public init(client: any MessagingClient) {
        self.client = client
    }

    public func callAsFunction(_ emoji: String, to message: MessageID, in conversation: ConversationID) async throws(MessagingError) {
        try await client.react(with: emoji, to: message, in: conversation)
    }
}
