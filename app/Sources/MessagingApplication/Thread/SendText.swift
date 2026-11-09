import Foundation
import MessagingDomain

/// Sends a text message. Surrounding whitespace is trimmed; blank messages are rejected
/// before they reach the network.
public struct SendText: Sendable {
    public enum Failure: Error, Equatable {
        case emptyMessage
        case messaging(MessagingError)
    }

    private let client: any MessagingClient

    public init(client: any MessagingClient) {
        self.client = client
    }

    public func callAsFunction(_ draft: String, to conversation: ConversationID, replyingTo original: MessageID? = nil) async throws(Failure) {
        guard let text = Self.sendableText(from: draft) else {
            throw .emptyMessage
        }
        do {
            try await client.sendText(text, to: conversation, replyingTo: original)
        } catch {
            throw .messaging(error)
        }
    }

    /// The text that would be sent for `draft`, or nil if there is nothing to send.
    public static func sendableText(from draft: String) -> String? {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
