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
        case sendAttachment(OutgoingAttachment, caption: String?, ConversationID)
        case contacts
        case conversation(withPhoneNumber: String)
        case sendReply(String, ConversationID, MessageID)
        case sendFileReply(OutgoingAttachment, caption: String?, ConversationID, MessageID)
        case react(String, MessageID, ConversationID)
        case deleteMessage(MessageID)
        case archive(ConversationID)
        case deleteConversation(ConversationID)
        case setMuted(Bool, ConversationID)
    }

    private struct Stubs {
        var connectError: MessagingError?
        var sendError: MessagingError?
        var unpairError: MessagingError?
        var pairingError: MessagingError?
        var pairingFailures: [MessagingError] = []
        var page = MessagePage(messages: [], olderCursor: nil)
        var attachment: Result<Data, MessagingError> = .success(Data())
        var avatars: Result<[ParticipantID: Data], MessagingError> = .success([:])
        var sendAttachmentError: MessagingError?
        var actionError: MessagingError?
        var contacts: Result<[Contact], MessagingError> = .success([])
        var conversation: Result<ConversationID, MessagingError> = .success(ConversationID("new"))
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
    /// Fails the next `times` pairings, then lets them through.
    public func stubPairing(failing error: MessagingError, times: Int) {
        stubs.withLock { $0.pairingFailures = Array(repeating: error, count: times) }
    }
    public func stubPage(_ page: MessagePage) { stubs.withLock { $0.page = page } }
    public func stubAttachment(_ result: Result<Data, MessagingError>) { stubs.withLock { $0.attachment = result } }
    public func stubAvatars(_ result: Result<[ParticipantID: Data], MessagingError>) { stubs.withLock { $0.avatars = result } }
    public func stubSendAttachmentError(_ error: MessagingError?) { stubs.withLock { $0.sendAttachmentError = error } }
    /// Makes reactions, deletes, archiving and muting fail.
    public func stubAction(throwing error: MessagingError) { stubs.withLock { $0.actionError = error } }
    public func stubContacts(_ result: Result<[Contact], MessagingError>) { stubs.withLock { $0.contacts = result } }
    public func stubConversation(_ result: Result<ConversationID, MessagingError>) { stubs.withLock { $0.conversation = result } }
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
        if let error = stubs.withLock({ $0.pairingFailures.popLast() ?? $0.pairingError }) { throw error }
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

    public func sendText(_ text: String, to conversation: ConversationID, replyingTo original: MessageID?) async throws(MessagingError) {
        record(original.map { .sendReply(text, conversation, $0) } ?? .sendText(text, conversation))
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

    public func sendAttachment(_ attachment: OutgoingAttachment, caption: String?, to conversation: ConversationID, replyingTo original: MessageID?) async throws(MessagingError) {
        record(original.map { .sendFileReply(attachment, caption: caption, conversation, $0) } ?? .sendAttachment(attachment, caption: caption, conversation))
        if let error = stubs.withLock({ $0.sendAttachmentError }) { throw error }
    }

    public func react(with emoji: String, to message: MessageID, in conversation: ConversationID) async throws(MessagingError) {
        try act(.react(emoji, message, conversation))
    }

    public func deleteMessage(_ message: MessageID) async throws(MessagingError) { try act(.deleteMessage(message)) }
    public func archive(_ conversation: ConversationID) async throws(MessagingError) { try act(.archive(conversation)) }
    public func delete(_ conversation: ConversationID) async throws(MessagingError) { try act(.deleteConversation(conversation)) }
    public func setMuted(_ isMuted: Bool, _ conversation: ConversationID) async throws(MessagingError) { try act(.setMuted(isMuted, conversation)) }

    private func act(_ call: Call) throws(MessagingError) {
        record(call)
        if let error = stubs.withLock({ $0.actionError }) { throw error }
    }

    public func avatars(for participants: Set<ParticipantID>) async throws(MessagingError) -> [ParticipantID: Data] {
        record(.avatars(participants))
        return try stubs.withLock { $0.avatars }.get()
    }

    public func contacts() async throws(MessagingError) -> [Contact] {
        record(.contacts)
        return try stubs.withLock { $0.contacts }.get()
    }

    public func conversation(withPhoneNumber number: String) async throws(MessagingError) -> ConversationID {
        record(.conversation(withPhoneNumber: number))
        return try stubs.withLock { $0.conversation }.get()
    }

    private func record(_ call: Call) { recorded.withLock { $0.append(call) } }
}
