import MessagingDomain

/// Streams new and updated messages for one conversation (delivery ticks, edits, deletions
/// arrive as the same message ID again with new state).
public struct ObserveThread: Sendable {
    private let client: any MessagingClient

    public init(client: any MessagingClient) {
        self.client = client
    }

    public func callAsFunction(_ conversation: ConversationID) -> AsyncStream<Message> {
        let events = client.events()
        return AsyncStream { continuation in
            let task = Task {
                for await event in events {
                    if let message = Self.message(in: conversation, from: event) {
                        continuation.yield(message)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func message(in conversation: ConversationID, from event: MessagingEvent) -> Message? {
        guard case .messageReceived(let message, _) = event, message.conversationID == conversation else {
            return nil
        }
        return message
    }
}
