import MessagingDomain

/// Sends a file, with the draft as its caption when there is one.
public struct SendAttachment: Sendable {
    private let client: any MessagingClient

    public init(client: any MessagingClient) {
        self.client = client
    }

    public func callAsFunction(_ attachment: OutgoingAttachment, caption draft: String, to conversation: ConversationID) async throws(MessagingError) {
        try await client.sendAttachment(attachment, caption: SendText.sendableText(from: draft), to: conversation)
    }
}
