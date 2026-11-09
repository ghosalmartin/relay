import Foundation

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

    /// Pairs using an account the user has signed in to. Suspends until the phone has accepted
    /// or refused. Progress arrives as `.pairingConfirmationEmoji`, then `.sessionChanged` and `.paired`.
    /// After `.paired` the client connects on its own; conversations then stream in.
    func startPairing(with cookies: AccountCookies) async throws(MessagingError)

    /// Connects with saved credentials. Conversations then stream in as events.
    func connect(using session: SessionData) async throws(MessagingError)
    func disconnect() async
    /// Revokes this device on the phone and forgets the session.
    func unpair() async throws(MessagingError)

    func messages(in conversation: ConversationID, before cursor: HistoryCursor?, limit: Int) async throws(MessagingError) -> MessagePage
    func sendText(_ text: String, to conversation: ConversationID, replyingTo original: MessageID?) async throws(MessagingError)
    /// Uploads a file and sends it, with any caption as part of the same message.
    func sendAttachment(_ attachment: OutgoingAttachment, caption: String?, to conversation: ConversationID, replyingTo original: MessageID?) async throws(MessagingError)
    func react(with emoji: String, to message: MessageID, in conversation: ConversationID) async throws(MessagingError)
    func deleteMessage(_ message: MessageID) async throws(MessagingError)
    func archive(_ conversation: ConversationID) async throws(MessagingError)
    func delete(_ conversation: ConversationID) async throws(MessagingError)
    func setMuted(_ isMuted: Bool, _ conversation: ConversationID) async throws(MessagingError)
    func markRead(_ conversation: ConversationID, upTo message: MessageID) async throws(MessagingError)
    /// The contents of a file attached to a message.
    func attachmentData(_ attachment: Attachment) async throws(MessagingError) -> Data
    /// Contact photos as image data. People without a photo are left out of the result.
    func avatars(for participants: Set<ParticipantID>) async throws(MessagingError) -> [ParticipantID: Data]
    /// The phone's address book.
    func contacts() async throws(MessagingError) -> [Contact]
    /// The conversation with this number, started if there isn't one yet. It also arrives as `.conversationUpdated`.
    func conversation(withPhoneNumber number: String) async throws(MessagingError) -> ConversationID
}

public extension MessagingClient {
    func sendText(_ text: String, to conversation: ConversationID) async throws(MessagingError) {
        try await sendText(text, to: conversation, replyingTo: nil)
    }

    func sendAttachment(_ attachment: OutgoingAttachment, caption: String?, to conversation: ConversationID) async throws(MessagingError) {
        try await sendAttachment(attachment, caption: caption, to: conversation, replyingTo: nil)
    }
}
