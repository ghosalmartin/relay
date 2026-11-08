import Foundation
import LibGMKit

/// Builds the request libgm needs to send text into a conversation.
/// The conversation supplies which of my numbers and SIM to send from.
enum SendRequestBuilder {
    static func textMessage(_ text: String, in conversation: GM.Conversation, transactionID: String = UUID().uuidString) -> GM.SendMessageRequest {
        var content = GM.MessageInfo()
        content.messageContent.content = text

        var payload = GM.MessagePayload()
        payload.tmpID = transactionID
        payload.tmpID2 = transactionID
        payload.conversationID = conversation.conversationID
        payload.participantID = conversation.defaultOutgoingID
        payload.messageInfo = [content]

        var request = GM.SendMessageRequest()
        request.conversationID = conversation.conversationID
        request.tmpID = transactionID
        request.messagePayload = payload
        if conversation.hasSimCard {
            request.simpayload = conversation.simCard.simdata.simpayload
        }
        return request
    }
}
