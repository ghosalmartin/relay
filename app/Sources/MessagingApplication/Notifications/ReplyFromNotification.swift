import MessagingDomain

/// Sends what was typed into an alert. Nothing else is on screen to show a failure,
/// so one arrives as another alert rather than the reply silently going missing.
public struct ReplyFromNotification: Sendable {
    private let sendText: SendText
    private let presenter: any NotificationPresenter

    public init(sendText: SendText, presenter: any NotificationPresenter) {
        self.sendText = sendText
        self.presenter = presenter
    }

    public func callAsFunction(_ text: String, to conversation: ConversationID) async {
        do {
            try await sendText(text, to: conversation)
        } catch {
            await presenter.present(MessageNotification(
                messageID: MessageID("reply-failed-\(conversation.rawValue)"),
                conversationID: conversation,
                title: "Message not sent",
                body: "Your reply didn't send: \(text)"
            ))
        }
    }
}
