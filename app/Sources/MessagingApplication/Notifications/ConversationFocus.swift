import MessagingDomain

/// Connects the app's window and the notification system: which conversation the user is
/// looking at, and which one they asked to open by clicking an alert.
public final class ConversationFocus: Sendable {
    public let attention = LiveValue(Attention())
    /// Live rather than an event, so a click still lands if the window takes a moment to open.
    public let openRequest = LiveValue<ConversationID?>(nil)

    public init() {}

    public func select(_ conversation: ConversationID?) {
        attention.update { Attention(selectedConversation: conversation, isAppActive: $0.isAppActive) }
    }

    public func setAppActive(_ isActive: Bool) {
        attention.update { Attention(selectedConversation: $0.selectedConversation, isAppActive: isActive) }
    }

    public func requestOpen(_ conversation: ConversationID) {
        openRequest.set(conversation)
    }

    public func isVisible(_ conversation: ConversationID) -> Bool {
        attention.value.visibleConversation == conversation
    }
}
