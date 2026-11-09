import LibGMKit
import MessagingDomain

/// Google Messages conversation → domain `Conversation`.
enum ConversationMapper {
    /// Spelled out as what leaves the inbox, so a status added later doesn't make conversations vanish.
    static func belongsInInbox(_ proto: GM.Conversation) -> Bool {
        ![.archived, .deleted, .keepArchived, .spamFolder, .blockedFolder, .crossCountryFolder, .trashFolder].contains(proto.status)
    }

    static func conversation(from proto: GM.Conversation) -> Conversation {
        Conversation(
            id: ConversationID(proto.conversationID),
            title: proto.name,
            preview: preview(from: proto),
            lastActivity: Timestamps.date(fromMicroseconds: proto.lastMessageTimestamp),
            isUnread: proto.unread,
            isGroup: proto.isGroupChat,
            participants: proto.participants.map(participant)
        )
    }

    static func participant(from proto: GM.Participant) -> Participant {
        Participant(
            id: ParticipantID(proto.id.participantID),
            displayName: displayName(of: proto),
            phoneNumber: proto.formattedNumber.isEmpty ? nil : proto.formattedNumber,
            isMe: proto.isMe
        )
    }

    private static func preview(from proto: GM.Conversation) -> MessagePreview? {
        guard proto.hasLatestMessage else { return nil }
        let latest = proto.latestMessage
        return MessagePreview(
            text: latest.displayContent,
            senderName: latest.displayName.isEmpty ? nil : latest.displayName,
            isFromMe: latest.fromMe != 0
        )
    }

    /// Best available name: full name, then first name, then the number.
    private static func displayName(of proto: GM.Participant) -> String {
        [proto.fullName, proto.firstName, proto.formattedNumber, proto.id.number]
            .first { !$0.isEmpty } ?? "Unknown"
    }
}
