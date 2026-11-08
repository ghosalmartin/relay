/// Failures a messaging client reports, in terms the app can act on.
public enum MessagingError: Error, Equatable, Sendable {
    /// No session yet, or it was revoked; pair first.
    case notPaired
    /// The phone did not answer in time.
    case phoneUnreachable
    case conversationNotFound(ConversationID)
    /// Anything else from the backend, with its message for logs and display.
    case backend(String)
}
