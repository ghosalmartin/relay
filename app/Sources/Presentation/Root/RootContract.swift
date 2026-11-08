import MessagingApplication

/// Which top-level screen the window shows.
public enum RootState: Equatable, Sendable {
    case launching
    case pairing
    case inbox
    case failed(message: String)
}

public enum RootIntent: Equatable, Sendable {
    case pairingFinished
    case retryTapped
    case signOutTapped
}

public enum RootMutation: Equatable, Sendable {
    case sessionStarted(StartSession.Outcome)
    case sessionFailed(String)
    case paired
    case connectionChanged(ConnectionStatus)
    case retrying
    case signedOut
}
