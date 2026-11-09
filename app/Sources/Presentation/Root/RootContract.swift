import MessagingApplication

/// Which top-level screen the window shows.
public enum RootState: Equatable, Sendable {
    case launching
    case pairing
    /// The one-off setup that lets Relay wake a stalled phone.
    case settingUpPhoneWake
    case inbox
    case failed(message: String)
}

public enum RootIntent: Equatable, Sendable {
    case pairingFinished
    case retryTapped
    case signOutTapped
    case phoneWakeSetupCompleted
    case phoneWakeSetupSkipped
}

public enum RootMutation: Equatable, Sendable {
    case sessionStarted(StartSession.Outcome)
    case sessionFailed(String)
    case paired
    case connectionChanged(ConnectionStatus)
    case retrying
    case signedOut
    case phoneWakeSetupNeeded
    case phoneWakeSetupEnded
}
