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
    public let reactions: [Reaction]
    /// What this message is answering, when it's a reply.
    public let replyPreview: String?
    /// Shown instead of the content when there's nothing to draw.
    public let placeholder: String?

    public var linkedText: AttributedString { LinkedText.attributed(text) }
    public var hasPicture: Bool { attachments.contains(where: \.isImage) }
    /// A deleted or unsupported message has nothing to reply to or react to.
    public var canTakeActions: Bool { placeholder == nil }
}

/// Turns a flat message list into day separators and grouped bubbles.
/// Messages from the same sender within `burstWindow` of each other form one burst.
public enum ThreadLayout {
    public static let burstWindow: TimeInterval = 5 * 60

    public static func items(for messages: [Message], in conversation: Conversation, calendar: Calendar) -> [ThreadItem] {
        let newestMine = messages.last(where: \.isFromMe)?.id
        let known = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        return messages.enumerated().flatMap { index, message -> [ThreadItem] in
            let previous = index > 0 ? messages[index - 1] : nil
            let following = index + 1 < messages.count ? messages[index + 1] : nil
            let startsDay = previous.map { !calendar.isDate($0.sentAt, inSameDayAs: message.sentAt) } ?? true
            let separator: [ThreadItem] = startsDay ? [.daySeparator(calendar.startOfDay(for: message.sentAt))] : []
            return separator + [.bubble(MessageBubble(
                id: message.id,
                text: message.text,
                attachments: message.parts.compactMap(attachment),
                sentAt: message.sentAt,
                isFromMe: message.isFromMe,
                senderName: startsBurst(message, after: previous, calendar: calendar)
                    ? senderName(of: message, in: conversation) : nil,
                endsBurst: !continuesBurst(message, with: following),
                status: message.id == newestMine ? message.status : nil,
                reactions: message.reactions,
                replyPreview: replyPreview(of: message, among: known),
                placeholder: placeholder(for: message)
            ))]
        }
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

    private static func replyPreview(of message: Message, among known: [MessageID: Message]) -> String? {
        guard let id = message.replyTo else { return nil }
        guard let original = known[id] else { return "Replying to an earlier message" }
        return original.text.isEmpty ? "Attachment" : original.text
    }

    private static func placeholder(for message: Message) -> String? {
        if message.status == .deleted { return "This message was deleted." }
        return message.parts.isEmpty ? "This kind of message isn't supported yet." : nil
    }

    private static func attachment(_ part: MessagePart) -> Attachment? {
        if case .attachment(let attachment) = part { return attachment }
        return nil
    }
}
