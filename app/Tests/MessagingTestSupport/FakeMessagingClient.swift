import AsyncBroadcast
import Foundation
import MessagingDomain
import Synchronization

/// A scriptable MessagingClient for tests. Push events with `emit`, stub results with
/// the `stub…` properties, and inspect what the code under test asked for in `calls`.
public final class FakeMessagingClient: MessagingClient, Sendable {
    public enum Call: Equatable, Sendable {
        case startPairing(AccountCookies), connect(SessionData), disconnect, unpair
        case messages(ConversationID, HistoryCursor?, limit: Int)
        case sendText(String, ConversationID)
        case markRead(ConversationID, MessageID)
        case attachmentData(Attachment)
        case avatars(Set<ParticipantID>)
    }

    private struct Stubs {
        var connectError: MessagingError?
        var sendError: MessagingError?
        var unpairError: MessagingError?
        var pairingError: MessagingError?
        var page = MessagePage(messages: [], olderCursor: nil)
        var attachment: Result<Data, MessagingError> = .success(Data())
        var avatars: Result<[ParticipantID: Data], MessagingError> = .success([:])
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
    public func stubUnpair(throwing error: MessagingError) { stubs.withLock { $0.unpairError = error } }
    public func stubPairing(throwing error: MessagingError) { stubs.withLock { $0.pairingError = error } }
    public func stubPage(_ page: MessagePage) { stubs.withLock { $0.page = page } }
    public func stubAttachment(_ result: Result<Data, MessagingError>) { stubs.withLock { $0.attachment = result } }
    public func stubAvatars(_ result: Result<[ParticipantID: Data], MessagingError>) { stubs.withLock { $0.avatars = result } }
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

    public func startPairing(with cookies: AccountCookies) async throws(MessagingError) {
        record(.startPairing(cookies))
        stubs.withLock { $0.eventsOnStartPairing }.forEach(emit)
        onStartPairing?()
        if let error = stubs.withLock({ $0.pairingError }) { throw error }
    }

    public func connect(using session: SessionData) async throws(MessagingError) {
        record(.connect(session))
        if let error = stubs.withLock({ $0.connectError }) { throw error }
    }

    public func disconnect() async { record(.disconnect) }
    public func unpair() async throws(MessagingError) {
        record(.unpair)
        emit(.loggedOut)
        if let error = stubs.withLock({ $0.unpairError }) { throw error }
    }

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

    public func attachmentData(_ attachment: Attachment) async throws(MessagingError) -> Data {
        record(.attachmentData(attachment))
        return try stubs.withLock { $0.attachment }.get()
    }

    public func avatars(for participants: Set<ParticipantID>) async throws(MessagingError) -> [ParticipantID: Data] {
        record(.avatars(participants))
        return try stubs.withLock { $0.avatars }.get()
    }

    private func record(_ call: Call) { recorded.withLock { $0.append(call) } }
}
