import MessagingDomain

/// Streams the inbox as it changes: one snapshot per change, newest activity first.
public struct ObserveInbox: Sendable {
    private let client: any MessagingClient

    public init(client: any MessagingClient) {
        self.client = client
    }

    public func callAsFunction() -> AsyncStream<InboxSnapshot> {
        let events = client.events()
        return AsyncStream { continuation in
            let task = Task {
                var inbox = InboxProjection()
                for await event in events where inbox.apply(event) {
                    continuation.yield(Self.snapshot(of: inbox))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func snapshot(of inbox: InboxProjection) -> InboxSnapshot {
        InboxSnapshot(conversations: inbox.conversations, isSyncing: !inbox.hasCompletedInitialSync)
    }
}
