/// Streams the connection status: the latest straight away, then each change.
public struct ObserveConnectionStatus: Sendable {
    private let session: LiveSession

    public init(session: LiveSession) {
        self.session = session
    }

    public func callAsFunction() -> AsyncStream<ConnectionStatus> {
        session.connection.values()
    }
}
