import AsyncBroadcast
import Foundation
import LibGMKit
import MessagingDomain
import OSLog
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
        /// So the first answer after a silence is announced, and the rest aren't.
        var phoneWentQuiet = false
    }

    private static let inboxSize: Int64 = 50
    private static let refused = MessagingError.backend("Your phone didn't accept that.")
    static let uploadFailed = MessagingError.backend("Couldn't upload that file. Check your connection and try again.")
    /// How long someone looking at a spinner should wait before the phone gets woken. libgm itself waits a minute,
    /// by which time a phone that has since woken up answers too late for the request to get its reply.
    static let answerExpected: Duration = .seconds(5)
    private static let log = Logger(subsystem: "dev.featurenotabug.Relay", category: "attachments")
    private static let avatarLog = Logger(subsystem: "dev.featurenotabug.Relay", category: "avatars")
    private static let wakeLog = Logger(subsystem: "dev.featurenotabug.Relay", category: "phone-wake")

    private let makeSession: GoogleMessagesSessionFactory
    private let broadcaster = Broadcaster<MessagingEvent>()
    private let state = Mutex(State())
    private let clock: any Clock<Duration>

    public init(makeSession: @escaping GoogleMessagesSessionFactory, clock: any Clock<Duration> = ContinuousClock()) {
        self.makeSession = makeSession
        self.clock = clock
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
        let response = try await noticingSlowPhone { () throws(MessagingError) in
            try await askPhone { () throws(LibGMError) in
                try await session.fetchMessages(
                    conversationID: conversation.rawValue,
                    count: Int64(limit),
                    before: cursor.flatMap(CursorCodec.cursor)
                )
            }
        }
        return MessagePage(
            messages: response.messages.compactMap(MessageMapper.message).sorted { $0.sentAt < $1.sentAt },
            olderCursor: response.hasCursor ? CursorCodec.token(from: response.cursor) : nil
        )
    }

    public func sendText(_ text: String, to conversation: ConversationID, replyingTo original: MessageID?) async throws(MessagingError) {
        let session = try currentSession()
        let known = try knownConversation(conversation)
        try await deliver(SendRequestBuilder.textMessage(text, in: known, replyingTo: original?.rawValue), on: session)
    }

    public func sendAttachment(_ attachment: OutgoingAttachment, caption: String?, to conversation: ConversationID, replyingTo original: MessageID?) async throws(MessagingError) {
        let session = try currentSession()
        let known = try knownConversation(conversation)
        let media = try await upload(attachment, on: session)
        try await deliver(SendRequestBuilder.mediaMessage(media, caption: caption, in: known, replyingTo: original?.rawValue), on: session)
    }

    /// The upload goes to Google, not the phone, so a timeout here means nothing was sent.
    private func upload(_ attachment: OutgoingAttachment, on session: any GoogleMessagesSession) async throws(MessagingError) -> GM.MediaContent {
        do {
            return try await session.uploadMedia(data: attachment.data, fileName: attachment.fileName, mimeType: attachment.mimeType)
        } catch {
            let failure = ErrorMapper.error(from: error)
            throw failure == .phoneUnreachable ? Self.uploadFailed : failure
        }
    }

    private func deliver(_ request: GM.SendMessageRequest, on session: any GoogleMessagesSession) async throws(MessagingError) {
        do {
            _ = try await noticingSlowPhone { () throws(LibGMError) in try await session.send(request) }
            notePhoneAnswered()
        } catch {
            // Recovery closes the old session while this may be in flight, and the phone can still act on it.
            if case .closed = error, state.withLock({ $0.session != nil }) { throw .phoneUnreachable }
            throw reported(ErrorMapper.error(from: error))
        }
    }

    public func react(with emoji: String, to message: MessageID, in conversation: ConversationID) async throws(MessagingError) {
        let session = try currentSession()
        let known = try knownConversation(conversation)
        let request = GM.SendReactionRequest.with {
            $0.messageID = message.rawValue
            $0.reactionData = ReactionMapper.data(for: emoji)
            $0.action = .add
            if known.hasSimCard {
                $0.simpayload = known.simCard.simdata.simpayload
            }
        }
        let response = try await askPhone { () throws(LibGMError) in try await session.react(request) }
        guard response.success else { throw Self.refused }
    }

    public func deleteMessage(_ message: MessageID) async throws(MessagingError) {
        let session = try currentSession()
        let response = try await askPhone { () throws(LibGMError) in try await session.deleteMessage(id: message.rawValue) }
        guard response.success else { throw Self.refused }
    }

    public func archive(_ conversation: ConversationID) async throws(MessagingError) {
        try await update(conversation) {
            $0.updateData = .with { data in
                data.conversationID = conversation.rawValue
                data.status = .archived
            }
        }
        forget(conversation)
    }

    public func delete(_ conversation: ConversationID) async throws(MessagingError) {
        // Asks for the number before the update, while the conversation is still remembered.
        let number = try ConversationMapper.conversation(from: knownConversation(conversation))
            .participants.first { !$0.isMe }?.phoneNumber
        try await update(conversation) {
            $0.action = .delete
            $0.deleteData = .with { data in
                data.conversationID = conversation.rawValue
                if let number { data.phone = number }
            }
        }
        forget(conversation)
    }

    public func setMuted(_ isMuted: Bool, _ conversation: ConversationID) async throws(MessagingError) {
        try await update(conversation) {
            $0.updateData = .with { data in
                data.conversationID = conversation.rawValue
                data.mute = isMuted ? .mute : .unmute
            }
        }
    }

    private func update(_ conversation: ConversationID, _ configure: (inout GM.UpdateConversationRequest) -> Void) async throws(MessagingError) {
        let session = try currentSession()
        let request = GM.UpdateConversationRequest.with {
            $0.conversationID = conversation.rawValue
            configure(&$0)
        }
        let response = try await askPhone { () throws(LibGMError) in try await session.updateConversation(request) }
        guard response.success else { throw Self.refused }
    }

    private func forget(_ conversation: ConversationID) {
        state.withLock { $0.conversations[conversation.rawValue] = nil }
        broadcaster.send(.conversationRemoved(conversation))
    }

    private func knownConversation(_ conversation: ConversationID) throws(MessagingError) -> GM.Conversation {
        guard let known = state.withLock({ $0.conversations[conversation.rawValue] }) else {
            throw .conversationNotFound(conversation)
        }
        return known
    }

    public func markRead(_ conversation: ConversationID, upTo message: MessageID) async throws(MessagingError) {
        let session = try currentSession()
        try await askPhone { () throws(LibGMError) in
            try await session.markRead(conversationID: conversation.rawValue, messageID: message.rawValue)
        }
    }

    public func attachmentData(_ attachment: Attachment) async throws(MessagingError) -> Data {
        if let inline = attachment.inlineData { return inline }
        let session = try currentSession()
        do {
            return try await mapErrors { () throws(LibGMError) in
                try await session.downloadMedia(id: attachment.id, key: attachment.accessKey)
            }
        } catch {
            Self.log.error("Attachment download failed (\(attachment.mimeType, privacy: .public)): \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    public func avatars(for participants: Set<ParticipantID>) async throws(MessagingError) -> [ParticipantID: Data] {
        let session = try currentSession()
        let response = try await askPhone { () throws(LibGMError) in
            try await session.participantThumbnails(ids: participants.map(\.rawValue))
        }
        let photos = Dictionary(
            response.thumbnail
                .filter { !$0.data.imageBuffer.isEmpty }
                .map { (ParticipantID($0.identifier), $0.data.imageBuffer) },
            uniquingKeysWith: { first, _ in first }
        )
        Self.avatarLog.notice("Asked for \(participants.count) avatars, phone returned \(response.thumbnail.count), \(photos.count) with photos")
        return photos
    }

    public func contacts() async throws(MessagingError) -> [Contact] {
        let session = try currentSession()
        return ContactMapper.contacts(from: try await askPhone { () throws(LibGMError) in try await session.listContacts() })
    }

    public func conversation(withPhoneNumber number: String) async throws(MessagingError) -> ConversationID {
        let session = try currentSession()
        let request = GM.GetOrCreateConversationRequest.with {
            $0.numbers = [.with {
                $0.mysteriousInt = 2    // the value libgm's own bridge sends
                $0.number = number
                $0.number2 = number
            }]
        }
        let response = try await askPhone { () throws(LibGMError) in try await session.getOrCreateConversation(request) }
        guard !response.conversation.conversationID.isEmpty else {
            throw .backend("Your phone couldn't start a conversation with that number.")
        }
        publish(.conversation(response.conversation))   // remembered too, because sending needs its details
        return ConversationID(response.conversation.conversationID)
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
            if case .phoneReachabilityChanged(let isReachable) = mapped {
                state.withLock { $0.phoneWentQuiet = !isReachable }
            }
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
            notePhoneAnswered()
            response.conversations.forEach { publish(.conversation($0)) }
            publish(.initialSyncDone)
        } catch {
            guard !Task.isCancelled else { return }
            state.withLock { $0.inboxLoad = nil }     // the phone's next settings message tries again
            // A late timeout says nothing about now: the phone may have answered something else meanwhile.
            guard ErrorMapper.error(from: error) != .phoneUnreachable else { return }
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
            throw reported(ErrorMapper.error(from: error))
        }
    }

    /// For requests only the phone can answer, unlike a download, which comes from Google.
    private func askPhone<T>(_ work: () async throws(LibGMError) -> T) async throws(MessagingError) -> T {
        let result = try await mapErrors(work)
        notePhoneAnswered()
        return result
    }

    /// For requests someone is waiting on. Background ones can be slow without it mattering.
    private func noticingSlowPhone<T, Failure: Error>(_ work: () async throws(Failure) -> T) async throws(Failure) -> T {
        let started = ContinuousClock.now
        let timer = Task { [weak self, clock] in
            guard (try? await clock.sleep(for: Self.answerExpected)) != nil, !Task.isCancelled else { return }
            self?.notePhoneSlow()
        }
        defer {
            timer.cancel()
            Self.wakeLog.notice("Waited \(String(describing: started.duration(to: .now)), privacy: .public) for the phone")
        }
        return try await work()
    }

    private func notePhoneSlow() {
        state.withLock { $0.phoneWentQuiet = true }
        broadcaster.send(.phoneSlowToAnswer)
    }

    /// libgm's own word on this can lag well behind a phone that is plainly answering again.
    private func notePhoneAnswered() {
        let wasQuiet = state.withLock { state in
            defer { state.phoneWentQuiet = false }
            return state.phoneWentQuiet
        }
        if wasQuiet { broadcaster.send(.phoneReachabilityChanged(isReachable: true)) }
    }

    /// libgm can go minutes without saying the phone has stopped answering, but a request that got no reply is proof.
    private func reported(_ failure: MessagingError) -> MessagingError {
        if failure == .phoneUnreachable {
            state.withLock { $0.phoneWentQuiet = true }
            broadcaster.send(.phoneReachabilityChanged(isReachable: false))
        }
        return failure
    }
}
