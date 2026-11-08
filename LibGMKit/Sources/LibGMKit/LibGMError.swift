/// Failures from LibGMKit.
public enum LibGMError: Error, Equatable, Sendable {
    /// The saved session blob could not be decoded; pair again.
    case invalidSavedSession
    /// The session was closed and can no longer be used.
    case closed
    /// A request could not be encoded, or a response could not be decoded.
    case malformed(String)
    /// libgm reported an error; the text is libgm's own.
    case bridge(String)
}
