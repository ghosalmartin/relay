import MessagingDomain

/// The app-wide view of the session: the inbox and the connection, kept current for as long
/// as the app runs.
///
/// libgm sends the first conversations as a burst straight after connecting, usually before
/// any screen exists. This subscribes on creation, so build it before anything can connect;
/// screens then read the latest state whenever they appear.
public final class LiveSession: Sendable {
    public let inbox = LiveValue(InboxSnapshot(conversations: [], isSyncing: true))
    public let connection = LiveValue(ConnectionStatus.connecting)
    /// Sooner than `connection`, which only gives up on the phone after libgm does.
    public let phoneNeedsWaking = LiveValue(false)

    private let events: AsyncStream<MessagingEvent>

    public init(client: any MessagingClient) {
        events = client.events()
    }

    /// Folds events into the live values until cancelled. Call once.
    public func run() async {
        _ = await events.reduce(InboxProjection()) { projection, event in
            let updated = projection.applying(event)
            if updated != projection {
                inbox.set(Self.snapshot(of: updated))
            }
            if let status = ConnectionStatus.after(event) {
                connection.set(status)
                phoneNeedsWaking.set(status == .phoneUnreachable)
            }
            if event == .phoneSlowToAnswer {
                phoneNeedsWaking.set(true)
            }
            return updated
        }
    }

    private static func snapshot(of projection: InboxProjection) -> InboxSnapshot {
        InboxSnapshot(conversations: projection.conversations, isSyncing: !projection.hasCompletedInitialSync)
    }
}
