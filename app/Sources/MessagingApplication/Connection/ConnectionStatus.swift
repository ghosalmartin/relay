import MessagingDomain

/// How the link to the phone is doing, for banners and the menu bar.
public enum ConnectionStatus: Equatable, Sendable {
    case connecting
    case online
    /// Connected to Google, but the phone isn't answering (asleep, offline, app killed).
    case phoneUnreachable
    /// Dropped for a moment; the client is retrying on its own.
    case reconnecting
    /// Gone for good; pair again.
    case lost(reason: String)
    case loggedOut

    /// The status after `event`, or nil if the event says nothing about the connection.
    public static func after(_ event: MessagingEvent) -> ConnectionStatus? {
        switch event {
        case .initialSyncCompleted, .connectionRestored: .online
        case .phoneReachabilityChanged(let isReachable): isReachable ? .online : .phoneUnreachable
        case .connectionInterrupted: .reconnecting
        case .connectionLost(let reason): .lost(reason: reason)
        case .loggedOut: .loggedOut
        default: nil
        }
    }
}
