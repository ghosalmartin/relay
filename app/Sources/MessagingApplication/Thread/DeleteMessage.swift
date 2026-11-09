import MessagingDomain

/// Deletes a message from the phone.
public struct DeleteMessage: Sendable {
    private let client: any MessagingClient

    public init(client: any MessagingClient) {
        self.client = client
    }

    public func callAsFunction(_ message: MessageID) async throws(MessagingError) {
        try await client.deleteMessage(message)
    }
}
