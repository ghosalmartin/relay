import Foundation
import LibGMKit

/// Builds the request libgm needs to send text into a conversation.
/// The conversation supplies which of my numbers and SIM to send from.
enum SendRequestBuilder {
    static func textMessage(_ text: String, in conversation: GM.Conversation, transactionID: String = UUID().uuidString) -> GM.SendMessageRequest {
        let content = GM.MessageInfo.with { $0.messageContent.content = text }
        let payload = GM.MessagePayload.with {
            $0.tmpID = transactionID
            $0.tmpID2 = transactionID
            $0.conversationID = conversation.conversationID
            $0.participantID = conversation.defaultOutgoingID
            $0.messageInfo = [content]
        }
        return GM.SendMessageRequest.with {
            $0.conversationID = conversation.conversationID
            $0.tmpID = transactionID
            $0.messagePayload = payload
            if conversation.hasSimCard {
                $0.simpayload = conversation.simCard.simdata.simpayload
            }
        }
    }
}
