import LibGMKit
import MessagingDomain

/// libgm event → domain event. Nil for events the app has no use for.
enum EventMapper {
    static func event(from event: LibGMEvent) -> MessagingEvent? {
        switch event {
        case .googleAccountEmoji(let emoji): .pairingConfirmationEmoji(emoji)
        case .paired: .paired
        case .sessionUpdated(let bytes): .sessionChanged(SessionData(bytes: bytes))
        case .initialSyncDone: .initialSyncCompleted
        case .conversation(let conversation) where !ConversationMapper.belongsInInbox(conversation):
            .conversationRemoved(ConversationID(conversation.conversationID))
        case .conversation(let conversation): .conversationUpdated(ConversationMapper.conversation(from: conversation))
        case .message(let message, let isHistorical): MessageMapper.message(from: message).map { .messageReceived($0, isHistorical: isHistorical) }
        case .typing(let typing): typingEvent(typing)
        case .phoneReachable(let isReachable): .phoneReachabilityChanged(isReachable: isReachable)
        case .transientError(let reason): .connectionInterrupted(reason: reason)
        case .connectionRecovered: .connectionRestored
        case .fatalError(let reason): .connectionLost(reason: reason)
        case .loggedOut: .loggedOut
        case .settings, .qrCode: nil
        }
    }

    private static func typingEvent(_ typing: GM.TypingData) -> MessagingEvent {
        .typingChanged(
            ConversationID(typing.conversationID),
            ParticipantID(typing.user.number),
            isTyping: typing.type == .startedTyping
        )
    }
}
