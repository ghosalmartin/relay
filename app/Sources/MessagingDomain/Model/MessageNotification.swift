import Foundation

/// An alert about an incoming message, already worded for display.
public struct MessageNotification: Equatable, Sendable {
    public let messageID: MessageID
    public let conversationID: ConversationID
    public let title: String
    public let body: String
    /// Absent when no photo has been loaded for the sender yet.
    public let senderPhoto: Data?

    public init(messageID: MessageID, conversationID: ConversationID, title: String, body: String, senderPhoto: Data? = nil) {
        self.senderPhoto = senderPhoto
        self.messageID = messageID
        self.conversationID = conversationID
        self.title = title
        self.body = body
    }

    public func withSenderPhoto(_ photo: Data?) -> MessageNotification {
        MessageNotification(messageID: messageID, conversationID: conversationID, title: title, body: body, senderPhoto: photo)
    }
}
