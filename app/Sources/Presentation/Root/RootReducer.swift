import MessagingApplication

public enum RootReducer: Reducer {
    public static func reduce(_ state: RootState, _ mutation: RootMutation) -> RootState {
        switch mutation {
        case .sessionStarted(.connected), .paired: .inbox
        case .sessionStarted(.needsPairing), .signedOut: .pairing
        case .sessionFailed(let message): .failed(message: message)
        case .retrying: .launching
        case .connectionChanged(let status): screen(state, after: status)
        }
    }

    /// Only a dead connection changes the screen; blips are shown as banners inside the inbox.
    private static func screen(_ state: RootState, after status: ConnectionStatus) -> RootState {
        switch status {
        case .loggedOut, .lost: .pairing
        case .connecting, .online, .phoneUnreachable, .reconnecting: state
        }
    }
}
