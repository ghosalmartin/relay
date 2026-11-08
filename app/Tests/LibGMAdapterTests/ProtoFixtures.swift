import LibGMKit

enum ProtoFixtures {
    static func conversation(_ id: String, name: String = "Sam", outgoingID: String = "me-1") -> GM.Conversation {
        GM.Conversation.with {
            $0.conversationID = id
            $0.name = name
            $0.defaultOutgoingID = outgoingID
            $0.lastMessageTimestamp = 1_700_000_000_000_000
        }
    }

    static func message(_ id: String, in conversation: String = "c1", status: GM.MessageStatusType = .incomingComplete, text: String = "hi", micros: Int64 = 1_700_000_000_000_000) -> GM.Message {
        GM.Message.with {
            $0.messageID = id
            $0.conversationID = conversation
            $0.participantID = "p1"
            $0.timestamp = micros
            $0.messageStatus.status = status
            $0.messageInfo = [GM.MessageInfo.with { $0.messageContent.content = text }]
        }
    }
}
