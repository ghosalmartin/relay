import AsyncBroadcast
import MessagingDomain
import Synchronization

/// A scriptable MessagingClient for tests. Push events with `emit`, stub results with
/// the `stub…` properties, and inspect what the code under test asked for in `calls`.
public final class FakeMessagingClient: MessagingClient, Sendable {
    public enum Call: Equatable, Sendable {
        case startPairing, refreshPairingCode, connect(SessionData), disconnect, unpair
        case messages(ConversationID, HistoryCursor?, limit: Int)
        case sendText(String, ConversationID)
        case markRead(ConversationID, MessageID)
    }

    private struct Stubs {
        var connectError: MessagingError?
        var sendError: MessagingError?
        var page = MessagePage(messages: [], olderCursor: nil)
        var eventsOnStartPairing: [MessagingEvent] = []
        var onStartPairing: (@Sendable () -> Void)?
        var onSendText: (@Sendable (String, ConversationID) -> Void)?
    }

    private let broadcaster = Broadcaster<MessagingEvent>()
    private let recorded = Mutex<[Call]>([])
    private let stubs = Mutex(Stubs())

    public init() {}

    // MARK: Scripting

    public func emit(_ event: MessagingEvent) { broadcaster.send(event) }
    public var calls: [Call] { recorded.withLock { $0 } }
    public var subscriberCount: Int { broadcaster.subscriberCount }

    public func stubConnect(throwing error: MessagingError) { stubs.withLock { $0.connectError = error } }
    public func stubSend(throwing error: MessagingError) { stubs.withLock { $0.sendError = error } }
    public func stubPage(_ page: MessagePage) { stubs.withLock { $0.page = page } }
    public func stubEventsOnStartPairing(_ events: [MessagingEvent]) { stubs.withLock { $0.eventsOnStartPairing = events } }

    /// Runs after `startPairing()`, e.g. to script a delayed `.paired` for UI tests.
    public var onStartPairing: (@Sendable () -> Void)? {
        get { stubs.withLock { $0.onStartPairing } }
        set { stubs.withLock { $0.onStartPairing = newValue } }
    }

    /// Runs after a successful `sendText`, e.g. to echo the message back.
    public var onSendText: (@Sendable (String, ConversationID) -> Void)? {
        get { stubs.withLock { $0.onSendText } }
        set { stubs.withLock { $0.onSendText = newValue } }
    }

    // MARK: MessagingClient

    public func events() -> AsyncStream<MessagingEvent> { broadcaster.subscribe() }

    public func startPairing() async throws(MessagingError) {
        record(.startPairing)
        stubs.withLock { $0.eventsOnStartPairing }.forEach(emit)
        onStartPairing?()
    }

    public func refreshPairingCode() async throws(MessagingError) { record(.refreshPairingCode) }

    public func connect(using session: SessionData) async throws(MessagingError) {
        record(.connect(session))
        if let error = stubs.withLock({ $0.connectError }) { throw error }
    }

    public func disconnect() async { record(.disconnect) }
    public func unpair() async throws(MessagingError) { record(.unpair) }

    public func messages(in conversation: ConversationID, before cursor: HistoryCursor?, limit: Int) async throws(MessagingError) -> MessagePage {
        record(.messages(conversation, cursor, limit: limit))
        return stubs.withLock { $0.page }
    }

    public func sendText(_ text: String, to conversation: ConversationID) async throws(MessagingError) {
        record(.sendText(text, conversation))
        if let error = stubs.withLock({ $0.sendError }) { throw error }
        onSendText?(text, conversation)
    }

    public func markRead(_ conversation: ConversationID, upTo message: MessageID) async throws(MessagingError) {
        record(.markRead(conversation, message))
    }

    private func record(_ call: Call) { recorded.withLock { $0.append(call) } }
}
