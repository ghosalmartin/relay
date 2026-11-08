import Foundation
import LibGMKit

/// Builds the request libgm needs to send into a conversation.
/// The conversation supplies which of my numbers and SIM to send from.
enum SendRequestBuilder {
    static func textMessage(_ text: String, in conversation: GM.Conversation, transactionID: String = UUID().uuidString) -> GM.SendMessageRequest {
        request(content: [.with { $0.messageContent.content = text }], in: conversation, transactionID: transactionID)
    }

    /// The file goes first and any caption after it, as libgm's own bridge sends them.
    static func mediaMessage(_ media: GM.MediaContent, caption: String?, in conversation: GM.Conversation, transactionID: String = UUID().uuidString) -> GM.SendMessageRequest {
        let file = GM.MessageInfo.with { $0.mediaContent = media }
        let text = caption.map { caption in GM.MessageInfo.with { $0.messageContent.content = caption } }
        return request(content: [file] + (text.map { [$0] } ?? []), in: conversation, transactionID: transactionID)
    }

    private static func request(content: [GM.MessageInfo], in conversation: GM.Conversation, transactionID: String) -> GM.SendMessageRequest {
        let payload = GM.MessagePayload.with {
            $0.tmpID = transactionID
            $0.tmpID2 = transactionID
            $0.conversationID = conversation.conversationID
            $0.participantID = conversation.defaultOutgoingID
            $0.messageInfo = content
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
