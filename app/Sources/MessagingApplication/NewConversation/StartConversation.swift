import MessagingDomain

/// Finds the conversation with a phone number, or starts one if there isn't any yet.
public struct StartConversation: Sendable {
    private let client: any MessagingClient

    public init(client: any MessagingClient) {
        self.client = client
    }

    public func callAsFunction(with phoneNumber: String) async throws(MessagingError) -> ConversationID {
        try await client.conversation(withPhoneNumber: phoneNumber)
    }
}
