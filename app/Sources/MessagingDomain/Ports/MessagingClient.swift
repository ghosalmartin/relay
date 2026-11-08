/// The port every messaging backend implements. libgm is one adapter; anything else
/// that can pair, sync and send can replace it without touching the rest of the app.
///
/// Contract:
/// - `events()` may be called any number of times; each call returns an independent
///   stream that receives every event from that moment on, and ends when the caller's
///   task is cancelled.
/// - Calls may suspend for network round trips and throw `MessagingError`.
public protocol MessagingClient: Sendable {
    func events() -> AsyncStream<MessagingEvent>

    /// Starts phone pairing. Progress arrives as `.pairingCode`, then `.paired` and `.sessionChanged`.
    /// After `.paired` the client connects on its own; conversations then stream in.
    func startPairing() async throws(MessagingError)
    /// Issues a fresh pairing code; codes expire after about 30 seconds.
    func refreshPairingCode() async throws(MessagingError)

    /// Connects with saved credentials. Conversations then stream in as events.
    func connect(using session: SessionData) async throws(MessagingError)
    func disconnect() async
    /// Revokes this device on the phone and forgets the session.
    func unpair() async throws(MessagingError)

    func messages(in conversation: ConversationID, before cursor: HistoryCursor?, limit: Int) async throws(MessagingError) -> MessagePage
    func sendText(_ text: String, to conversation: ConversationID) async throws(MessagingError)
    func markRead(_ conversation: ConversationID, upTo message: MessageID) async throws(MessagingError)
}
