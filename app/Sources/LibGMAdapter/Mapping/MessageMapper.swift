import LibGMKit
import MessagingDomain

/// Google Messages message → domain `Message`.
enum MessageMapper {
    /// Nil for system notices ("Sam joined", "switched to RCS"), which aren't chat messages.
    static func message(from proto: GM.Message) -> Message? {
        let kind = StatusKind(proto.messageStatus.status)
        guard kind != .systemNotice else { return nil }
        return Message(
            id: MessageID(proto.messageID),
            conversationID: ConversationID(proto.conversationID),
            sender: kind == .outgoing ? .me : .participant(ParticipantID(proto.participantID)),
            sentAt: Timestamps.date(fromMicroseconds: proto.timestamp),
            parts: proto.messageInfo.compactMap(part),
            status: deliveryStatus(proto.messageStatus.status)
        )
    }

    static func part(from info: GM.MessageInfo) -> MessagePart? {
        switch info.data {
        case .messageContent(let content):
            return .text(content.content)
        case .mediaContent(let media):
            return .attachment(Attachment(
                id: media.mediaID,
                fileName: media.mediaName,
                mimeType: media.mimeType,
                byteCount: media.size > 0 ? media.size : nil
            ))
        case .locationContent, .none:
            return nil
        }
    }

    static func deliveryStatus(_ status: GM.MessageStatusType) -> DeliveryStatus {
        switch status {
        case .outgoingComplete: .sent
        case .outgoingDelivered: .delivered
        case .outgoingDisplayed: .read
        case .outgoingDeleted, .incomingDeleted, .messageDeleted: .deleted
        default:
            switch StatusKind(status) {
            case .outgoing: isFailure(status) ? .failed : .sending
            case .incoming, .systemNotice, .unknown: .received
            }
        }
    }

    private static func isFailure(_ status: GM.MessageStatusType) -> Bool {
        switch status {
        case .outgoingCanceled, .outgoingRestricted, .outgoingFailedGeneric, .outgoingFailedEmergencyNumber,
             .outgoingFailedTooLarge, .outgoingFailedRecipientLostRcs, .outgoingFailedNoRetryNoFallback,
             .outgoingFailedRecipientDidNotDecrypt, .outgoingFailedRecipientLostEncryption,
             .outgoingFailedRecipientDidNotDecryptNoMoreRetry, .outgoingFailedRecipientNegativeDelivery,
             .outgoingFailedToEncrypt:
            true
        default:
            false
        }
    }

    /// libgm groups status codes by range: 1–99 outgoing, 100–199 incoming,
    /// 200–299 system notices ("tombstones"), 300 deleted.
    enum StatusKind {
        case outgoing, incoming, systemNotice, unknown

        init(_ status: GM.MessageStatusType) {
            switch status.rawValue {
            case 1..<100: self = .outgoing
            case 100..<200: self = .incoming
            case 200..<300: self = .systemNotice
            default: self = .unknown
            }
        }
    }
}
