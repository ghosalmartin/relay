import Foundation
import MessagingDomain

/// One thing the thread view draws.
public enum ThreadItem: Identifiable, Equatable, Sendable {
    case daySeparator(Date)
    case bubble(MessageBubble)

    public var id: String {
        switch self {
        case .daySeparator(let day): "day-\(day.timeIntervalSince1970)"
        case .bubble(let bubble): "msg-\(bubble.id.rawValue)"
        }
    }
}

/// A message as a bubble: who it's from, and how it sits among its neighbours.
public struct MessageBubble: Identifiable, Equatable, Sendable {
    public let id: MessageID
    public let text: String
    public let attachments: [Attachment]
    public let sentAt: Date
    public let isFromMe: Bool
    /// Shown above the first bubble of a burst in group chats.
    public let senderName: String?
    /// Last bubble of a burst: gets the tail and the timestamp.
    public let endsBurst: Bool
    /// Delivery status, only on my most recent message.
    public let status: DeliveryStatus?
}

/// Turns a flat message list into day separators and grouped bubbles.
/// Messages from the same sender within `burstWindow` of each other form one burst.
public enum ThreadLayout {
    public static let burstWindow: TimeInterval = 5 * 60

    public static func items(for messages: [Message], in conversation: Conversation, calendar: Calendar) -> [ThreadItem] {
        let newestMine = messages.last(where: \.isFromMe)?.id
        var items: [ThreadItem] = []
        for (index, message) in messages.enumerated() {
            let previous = index > 0 ? messages[index - 1] : nil
            let following = index + 1 < messages.count ? messages[index + 1] : nil
            if previous.map({ !calendar.isDate($0.sentAt, inSameDayAs: message.sentAt) }) ?? true {
                items.append(.daySeparator(calendar.startOfDay(for: message.sentAt)))
            }
            items.append(.bubble(MessageBubble(
                id: message.id,
                text: message.text,
                attachments: message.parts.compactMap(attachment),
                sentAt: message.sentAt,
                isFromMe: message.isFromMe,
                senderName: startsBurst(message, after: previous, calendar: calendar)
                    ? senderName(of: message, in: conversation) : nil,
                endsBurst: !continuesBurst(message, with: following),
                status: message.id == newestMine ? message.status : nil
            )))
        }
        return items
    }

    static func continuesBurst(_ message: Message, with next: Message?) -> Bool {
        guard let next else { return false }
        return next.sender == message.sender && next.sentAt.timeIntervalSince(message.sentAt) <= burstWindow
    }

    private static func startsBurst(_ message: Message, after previous: Message?, calendar: Calendar) -> Bool {
        guard let previous else { return true }
        let sameDay = calendar.isDate(previous.sentAt, inSameDayAs: message.sentAt)
        return !(sameDay && continuesBurst(previous, with: message))
    }

    /// Names only matter in groups, and never for my own messages.
    private static func senderName(of message: Message, in conversation: Conversation) -> String? {
        guard conversation.isGroup, case .participant(let id) = message.sender else { return nil }
        return conversation.participants.first { $0.id == id }?.displayName
    }

    private static func attachment(_ part: MessagePart) -> Attachment? {
        if case .attachment(let attachment) = part { return attachment }
        return nil
    }
}
