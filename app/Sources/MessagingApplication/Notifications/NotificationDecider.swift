import MessagingDomain

/// Decides which events deserve an alert and how to word it. Pure value type: no I/O, no time.
struct NotificationDecider {
    /// Enough to catch repeats (delivery updates, reconnects) without growing forever.
    static let rememberedMessageLimit = 1_000

    /// What to do about one event, and the decider to use for the next.
    struct Decision {
        let next: NotificationDecider
        let notification: MessageNotification?
        /// Who the alert is about, for finding their photo.
        let sender: ParticipantID?

        init(next: NotificationDecider, notification: MessageNotification?, sender: ParticipantID? = nil) {
            self.next = next
            self.notification = notification
            self.sender = sender
        }
    }

    let inbox: InboxProjection
    private let seen: [MessageID]

    init() {
        self.init(inbox: InboxProjection(), seen: [])
    }

    private init(inbox: InboxProjection, seen: [MessageID]) {
        self.inbox = inbox
        self.seen = seen
    }

    func deciding(_ event: MessagingEvent, visible: ConversationID?) -> Decision {
        let updated = NotificationDecider(inbox: inbox.applying(event), seen: seen)
        guard case .messageReceived(let message, let isHistorical) = event, !seen.contains(message.id) else {
            return Decision(next: updated, notification: nil)
        }
        let remembered = updated.remembering(message.id)
        // Anything arriving before the first sync finishes is catch-up, not news.
        guard !isHistorical, updated.inbox.hasCompletedInitialSync,
              !message.isFromMe, message.status == .received,
              message.conversationID != visible else {
            return Decision(next: remembered, notification: nil)
        }
        let conversation = updated.inbox.conversations.first { $0.id == message.conversationID }
        return Decision(next: remembered, notification: MessageNotification(
            messageID: message.id,
            conversationID: message.conversationID,
            title: conversation?.title ?? "New Message",
            body: Self.body(of: message, in: conversation)
        ), sender: Self.participant(sending: message))
    }

    private func remembering(_ id: MessageID) -> NotificationDecider {
        NotificationDecider(inbox: inbox, seen: (seen + [id]).suffix(Self.rememberedMessageLimit))
    }

    private static func body(of message: Message, in conversation: Conversation?) -> String {
        let content = message.text.isEmpty ? attachmentLabel(of: message) : message.text
        guard let conversation, conversation.isGroup, let sender = senderName(of: message, in: conversation) else {
            return content
        }
        return "\(sender): \(content)"
    }

    private static func attachmentLabel(of message: Message) -> String {
        let isImage = message.parts.contains {
            if case .attachment(let attachment) = $0 { return attachment.isImage }
            return false
        }
        return isImage ? "Photo" : "Attachment"
    }

    private static func senderName(of message: Message, in conversation: Conversation) -> String? {
        guard let id = participant(sending: message) else { return nil }
        return conversation.participants.first { $0.id == id }?.displayName
    }

    private static func participant(sending message: Message) -> ParticipantID? {
        guard case .participant(let id) = message.sender else { return nil }
        return id
    }
}
