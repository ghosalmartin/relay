import LibGMKit

enum ProtoFixtures {
    static func conversation(_ id: String, name: String = "Sam", outgoingID: String = "me-1") -> GM.Conversation {
        var conversation = GM.Conversation()
        conversation.conversationID = id
        conversation.name = name
        conversation.defaultOutgoingID = outgoingID
        conversation.lastMessageTimestamp = 1_700_000_000_000_000
        return conversation
    }

    static func message(_ id: String, in conversation: String = "c1", status: GM.MessageStatusType = .incomingComplete, text: String = "hi", micros: Int64 = 1_700_000_000_000_000) -> GM.Message {
        var message = GM.Message()
        message.messageID = id
        message.conversationID = conversation
        message.participantID = "p1"
        message.timestamp = micros
        message.messageStatus.status = status
        var info = GM.MessageInfo()
        info.messageContent.content = text
        message.messageInfo = [info]
        return message
    }
}
