import Foundation

/// A single message in a thread.
public struct Message: Identifiable, Hashable, Sendable {
    public let id: MessageID
    public let conversationID: ConversationID
    public let sender: Sender
    public let sentAt: Date
    public let parts: [MessagePart]
    public let status: DeliveryStatus

    public init(
        id: MessageID,
        conversationID: ConversationID,
        sender: Sender,
        sentAt: Date,
        parts: [MessagePart],
        status: DeliveryStatus
    ) {
        self.id = id
        self.conversationID = conversationID
        self.sender = sender
        self.sentAt = sentAt
        self.parts = parts
        self.status = status
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

    public init(id: String, fileName: String, mimeType: String, byteCount: Int64?) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.byteCount = byteCount
    }

    public var isImage: Bool { mimeType.hasPrefix("image/") }
}

public enum DeliveryStatus: Hashable, Sendable {
    case sending, sent, delivered, read, failed, received, deleted
}
