/// An alert about an incoming message, already worded for display.
public struct MessageNotification: Equatable, Sendable {
    public let messageID: MessageID
    public let conversationID: ConversationID
    public let title: String
    public let body: String

    public init(messageID: MessageID, conversationID: ConversationID, title: String, body: String) {
        self.messageID = messageID
        self.conversationID = conversationID
        self.title = title
        self.body = body
    }
}
