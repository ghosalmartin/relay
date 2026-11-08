/// Streams the inbox: the latest snapshot straight away, then one per change, newest activity first.
public struct ObserveInbox: Sendable {
    private let session: LiveSession

    public init(session: LiveSession) {
        self.session = session
    }

    public func callAsFunction() -> AsyncStream<InboxSnapshot> {
        session.inbox.values()
    }
}
