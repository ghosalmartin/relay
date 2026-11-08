/// Everything a messaging client can tell the app, in domain terms.
public enum MessagingEvent: Sendable, Equatable {
    /// A pairing code to show the user, typically rendered as a QR code. Replaces any earlier code.
    case pairingCode(String)
    /// An emoji the user must confirm on their phone (Google-account pairing).
    case pairingConfirmationEmoji(String)
    case paired
    /// Credentials changed and must be persisted.
    case sessionChanged(SessionData)
    /// The first batch of conversations after connecting has been delivered.
    case initialSyncCompleted
    case conversationUpdated(Conversation)
    case messageReceived(Message, isHistorical: Bool)
    case typingChanged(ConversationID, ParticipantID, isTyping: Bool)
    case phoneReachabilityChanged(isReachable: Bool)
    case connectionInterrupted(reason: String)
    case connectionRestored
    /// The connection is gone for good; the user has to pair again.
    case connectionLost(reason: String)
    case loggedOut
}
