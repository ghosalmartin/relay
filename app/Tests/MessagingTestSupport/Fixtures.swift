import Foundation
import MessagingDomain

/// Builders with sensible defaults, so each test states only what it cares about.
public enum Fixtures {
    public static func conversation(
        _ id: String,
        title: String = "Alex",
        lastActivity: Date = Date(timeIntervalSince1970: 0),
        isUnread: Bool = false,
        preview: String? = nil
    ) -> Conversation {
        Conversation(
            id: ConversationID(id),
            title: title,
            preview: preview.map { MessagePreview(text: $0, senderName: nil, isFromMe: false) },
            lastActivity: lastActivity,
            isUnread: isUnread,
            isGroup: false,
            participants: []
        )
    }

    public static func message(
        _ id: String,
        in conversation: String = "c1",
        text: String = "hi",
        from sender: Sender = .participant(ParticipantID("p1")),
        sentAt: Date = Date(timeIntervalSince1970: 0),
        status: DeliveryStatus = .received
    ) -> Message {
        Message(
            id: MessageID(id),
            conversationID: ConversationID(conversation),
            sender: sender,
            sentAt: sentAt,
            parts: [.text(text)],
            status: status
        )
    }

    public static let session = SessionData(bytes: Data("session".utf8))
    public static let accountCookies = AccountCookies(values: ["SID": "cookie"])
}
