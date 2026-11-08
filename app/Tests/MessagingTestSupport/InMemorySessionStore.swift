import MessagingDomain
import Synchronization

public final class InMemorySessionStore: SessionStore, Sendable {
    private let stored: Mutex<SessionData?>

    public init(_ session: SessionData? = nil) { stored = Mutex(session) }

    public var session: SessionData? { stored.withLock { $0 } }

    public func load() async throws -> SessionData? { session }
    public func save(_ session: SessionData) async throws { stored.withLock { $0 = session } }
    public func clear() async throws { stored.withLock { $0 = nil } }
}
