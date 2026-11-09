/// Everything a messaging client can tell the app, in domain terms.
public enum MessagingEvent: Sendable, Equatable {
    /// An emoji the user must tap on their phone to finish pairing.
    case pairingConfirmationEmoji(String)
    case paired
    /// Credentials changed and must be persisted.
    case sessionChanged(SessionData)
    /// The first batch of conversations after connecting has been delivered.
    case initialSyncCompleted
    case conversationUpdated(Conversation)
    /// Archived, deleted or otherwise moved out of the inbox.
    case conversationRemoved(ConversationID)
    case messageReceived(Message, isHistorical: Bool)
    case typingChanged(ConversationID, ParticipantID, isTyping: Bool)
    case phoneReachabilityChanged(isReachable: Bool)
    /// A request someone is waiting on has gone unanswered for a few seconds. It may yet be answered.
    case phoneSlowToAnswer
    case connectionInterrupted(reason: String)
    case connectionRestored
    /// The connection is gone for good; the user has to pair again.
    case connectionLost(reason: String)
    case loggedOut
}
