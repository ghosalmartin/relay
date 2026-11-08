import MessagingDomain

/// What the user could be looking at right now.
public struct Attention: Equatable, Sendable {
    public let selectedConversation: ConversationID?
    public let isAppActive: Bool

    public init(selectedConversation: ConversationID? = nil, isAppActive: Bool = false) {
        self.selectedConversation = selectedConversation
        self.isAppActive = isAppActive
    }

    /// Only counts while the app is frontmost: a conversation left open behind another app isn't being read.
    public var visibleConversation: ConversationID? {
        isAppActive ? selectedConversation : nil
    }
}
