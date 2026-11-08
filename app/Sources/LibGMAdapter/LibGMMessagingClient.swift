import AsyncBroadcast
import Foundation
import LibGMKit
import MessagingDomain
import Synchronization

/// `MessagingClient` backed by libgm. The only type in the app that knows libgm exists.
///
/// Owns at most one live session. Its events are mapped to domain events and fanned out
/// to every subscriber. Conversations are remembered because sending needs details
/// (which number and SIM to send from) that the domain deliberately doesn't carry.
public final class LibGMMessagingClient: MessagingClient {
    private struct State {
        var session: (any GoogleMessagesSession)?
        var pump: Task<Void, Never>?
        var conversations: [String: GM.Conversation] = [:]
        var inboxLoad: Task<Void, Never>?
    }

    private static let inboxSize: Int64 = 50

    private let makeSession: GoogleMessagesSessionFactory
    private let broadcaster = Broadcaster<MessagingEvent>()
    private let state = Mutex(State())

    public init(makeSession: @escaping GoogleMessagesSessionFactory) {
        self.makeSession = makeSession
    }

    /// The production client, backed by the native libgm library.
    public static func live() -> LibGMMessagingClient {
        LibGMMessagingClient { savedSession throws(LibGMError) in try LibGMSession(savedSession: savedSession) }
    }

    public func events() -> AsyncStream<MessagingEvent> {
        broadcaster.subscribe()
    }

    // MARK: Pairing and connection

    public func startPairing(with cookies: AccountCookies) async throws(MessagingError) {
        let session = try replaceSession(savedSession: nil)
        try await mapErrors { () throws(LibGMError) in try await session.startGoogleAccountPairing(cookies: cookies.values) }
    }

    public func connect(using session: SessionData) async throws(MessagingError) {
        let live = try replaceSession(savedSession: session.bytes)
        try await mapErrors { () throws(LibGMError) in try await live.connect() }
    }

    public func disconnect() async {
        await state.withLock { $0.session }?.disconnect()
    }

    public func unpair() async throws(MessagingError) {
        let session = try currentSession()
        // Even if the phone can't be told, this device has stopped being paired.
        defer {
            endSession()
            broadcaster.send(.loggedOut)
        }
        try await mapErrors { () throws(LibGMError) in try await session.unpair() }
    }

    // MARK: Messages

    public func messages(in conversation: ConversationID, before cursor: HistoryCursor?, limit: Int) async throws(MessagingError) -> MessagePage {
        let session = try currentSession()
        let response = try await mapErrors { () throws(LibGMError) in
            try await session.fetchMessages(
                conversationID: conversation.rawValue,
                count: Int64(limit),
                before: cursor.flatMap(CursorCodec.cursor)
            )
        }
        return MessagePage(
            messages: response.messages.compactMap(MessageMapper.message).sorted { $0.sentAt < $1.sentAt },
            olderCursor: response.hasCursor ? CursorCodec.token(from: response.cursor) : nil
        )
    }

    public func sendText(_ text: String, to conversation: ConversationID) async throws(MessagingError) {
        let session = try currentSession()
        guard let known = state.withLock({ $0.conversations[conversation.rawValue] }) else {
            throw .conversationNotFound(conversation)
        }
        let request = SendRequestBuilder.textMessage(text, in: known)
        _ = try await mapErrors { () throws(LibGMError) in try await session.send(request) }
    }

    public func markRead(_ conversation: ConversationID, upTo message: MessageID) async throws(MessagingError) {
        let session = try currentSession()
        try await mapErrors { () throws(LibGMError) in
            try await session.markRead(conversationID: conversation.rawValue, messageID: message.rawValue)
        }
    }

    // MARK: Session lifecycle

    /// Closes any current session and starts a new one whose events feed the broadcaster.
    private func replaceSession(savedSession: Data?) throws(MessagingError) -> any GoogleMessagesSession {
        let session: any GoogleMessagesSession
        do {
            session = try makeSession(savedSession)
        } catch {
            throw ErrorMapper.error(from: error)
        }
        let pump = Task { [weak self] in
            for await event in session.events {
                self?.handle(event, from: session)
            }
        }
        let previous = state.withLock { state in
            defer {
                state.session = session
                state.pump = pump
                state.inboxLoad = nil
            }
            return (state.session, state.pump, state.inboxLoad)
        }
        previous.2?.cancel()
        previous.1?.cancel()
        previous.0?.close()
        return session
    }

    private func endSession() {
        let previous = state.withLock { state in
            defer { state = State() }
            return (state.session, state.pump, state.inboxLoad)
        }
        previous.2?.cancel()
        previous.1?.cancel()
        previous.0?.close()
    }

    private func currentSession() throws(MessagingError) -> any GoogleMessagesSession {
        guard let session = state.withLock({ $0.session }) else { throw .notPaired }
        return session
    }

    private func handle(_ event: LibGMEvent, from session: any GoogleMessagesSession) {
        publish(event)
        // libgm no longer announces a first sync. Its first settings message follows the phone
        // accepting this session as active, so that's when asking for conversations gets an answer.
        if case .settings = event {
            startInboxLoadIfNeeded(from: session)
        }
    }

    private func publish(_ event: LibGMEvent) {
        remember(event)
        if let mapped = EventMapper.event(from: event) {
            broadcaster.send(mapped)
        }
    }

    /// Runs apart from the event pump: the phone may be slow to answer, and word of that arrives as an event.
    private func startInboxLoadIfNeeded(from session: any GoogleMessagesSession) {
        state.withLock { state in
            guard state.inboxLoad == nil else { return }
            state.inboxLoad = Task { [weak self] in await self?.loadInbox(from: session) }
        }
    }

    private func loadInbox(from session: any GoogleMessagesSession) async {
        let request = GM.ListConversationsRequest.with {
            $0.count = Self.inboxSize
            $0.folder = .inbox
        }
        do {
            let response = try await session.listConversations(request)
            guard !Task.isCancelled else { return }
            response.conversations.forEach { publish(.conversation($0)) }
            publish(.initialSyncDone)
        } catch {
            guard !Task.isCancelled else { return }
            state.withLock { $0.inboxLoad = nil }     // the phone's next settings message tries again
            publish(.transientError("Couldn't load your conversations."))
        }
    }

    private func remember(_ event: LibGMEvent) {
        switch event {
        case .conversation(let conversation):
            state.withLock { $0.conversations[conversation.conversationID] = conversation }
        case .loggedOut:
            state.withLock { $0.conversations.removeAll() }
        default:
            break
        }
    }

    private func mapErrors<T>(_ work: () async throws(LibGMError) -> T) async throws(MessagingError) -> T {
        do {
            return try await work()
        } catch {
            throw ErrorMapper.error(from: error)
        }
    }
}
