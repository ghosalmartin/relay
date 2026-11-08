import Foundation

/// A single message in a thread.
public struct Message: Identifiable, Hashable, Sendable {
    public let id: MessageID
    public let conversationID: ConversationID
    public let sender: Sender
    public let sentAt: Date
    public let parts: [MessagePart]
    public let status: DeliveryStatus
    public let reactions: [Reaction]
    /// The message this one answers, when it was sent as a reply.
    public let replyTo: MessageID?

    public init(
        id: MessageID,
        conversationID: ConversationID,
        sender: Sender,
        sentAt: Date,
        parts: [MessagePart],
        status: DeliveryStatus,
        reactions: [Reaction] = [],
        replyTo: MessageID? = nil
    ) {
        self.id = id
        self.conversationID = conversationID
        self.sender = sender
        self.sentAt = sentAt
        self.parts = parts
        self.status = status
        self.reactions = reactions
        self.replyTo = replyTo
    }

    public var isFromMe: Bool { sender == .me }

    /// All text parts joined, for previews, search and notifications.
    public var text: String {
        parts.compactMap(\.text).joined(separator: "\n")
    }
}

public enum Sender: Hashable, Sendable {
    case me
    case participant(ParticipantID)
}

public enum MessagePart: Hashable, Sendable {
    case text(String)
    case attachment(Attachment)

    public var text: String? {
        if case .text(let value) = self { return value }
        return nil
    }
}

public struct Attachment: Hashable, Sendable {
    public let id: String
    public let fileName: String
    public let mimeType: String
    public let byteCount: Int64?
    /// Opaque to the app: whatever the messaging backend needs to fetch this file.
    public let accessKey: Data
    /// The file itself, when it came inside the message rather than needing a download.
    public let inlineData: Data?

    public init(id: String, fileName: String, mimeType: String, byteCount: Int64?, accessKey: Data = Data(), inlineData: Data? = nil) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.accessKey = accessKey
        self.inlineData = inlineData
    }

    public var isImage: Bool { mimeType.hasPrefix("image/") }
}

/// One emoji on a message and how many people used it.
public struct Reaction: Hashable, Sendable {
    public let emoji: String
    public let count: Int

    public init(emoji: String, count: Int) {
        self.emoji = emoji
        self.count = count
    }
}

public enum DeliveryStatus: Hashable, Sendable {
    case sending, sent, delivered, read, failed, received, deleted
}
