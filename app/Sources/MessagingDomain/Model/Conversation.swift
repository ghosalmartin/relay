import Foundation

/// A thread as shown in the inbox.
public struct Conversation: Identifiable, Hashable, Sendable {
    public let id: ConversationID
    public let title: String
    public let preview: MessagePreview?
    public let lastActivity: Date
    public let isUnread: Bool
    public let isGroup: Bool
    public let participants: [Participant]

    public init(
        id: ConversationID,
        title: String,
        preview: MessagePreview?,
        lastActivity: Date,
        isUnread: Bool,
        isGroup: Bool,
        participants: [Participant]
    ) {
        self.id = id
        self.title = title
        self.preview = preview
        self.lastActivity = lastActivity
        self.isUnread = isUnread
        self.isGroup = isGroup
        self.participants = participants
    }

    /// Whose photo represents this conversation. Groups have no single person to show.
    public var avatarParticipant: ParticipantID? {
        isGroup ? nil : participants.first { !$0.isMe }?.id
    }

    public func markingRead() -> Conversation {
        Conversation(id: id, title: title, preview: preview, lastActivity: lastActivity,
                     isUnread: false, isGroup: isGroup, participants: participants)
    }
}

/// The one-line summary of the latest message, shown under the conversation title.
public struct MessagePreview: Hashable, Sendable {
    public let text: String
    public let senderName: String?
    public let isFromMe: Bool

    public init(text: String, senderName: String?, isFromMe: Bool) {
        self.text = text
        self.senderName = senderName
        self.isFromMe = isFromMe
    }
}
