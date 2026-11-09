import Foundation
import LibGMKit

/// The slice of `LibGMSession` this adapter uses. Depending on a protocol keeps
/// `LibGMMessagingClient` testable without the native library.
public protocol GoogleMessagesSession: Sendable {
    var events: AsyncStream<LibGMEvent> { get }
    func startGoogleAccountPairing(cookies: [String: String]) async throws(LibGMError)
    func connect() async throws(LibGMError)
    func disconnect() async
    func unpair() async throws(LibGMError)
    func close()
    func listConversations(_ request: GM.ListConversationsRequest) async throws(LibGMError) -> GM.ListConversationsResponse
    func fetchMessages(conversationID: String, count: Int64, before cursor: GM.Cursor?) async throws(LibGMError) -> GM.ListMessagesResponse
    func send(_ request: GM.SendMessageRequest) async throws(LibGMError) -> GM.SendMessageResponse
    func markRead(conversationID: String, messageID: String) async throws(LibGMError)
    func downloadMedia(id: String, key: Data) async throws(LibGMError) -> Data
    func participantThumbnails(ids: [String]) async throws(LibGMError) -> GM.GetThumbnailResponse
    func uploadMedia(data: Data, fileName: String, mimeType: String) async throws(LibGMError) -> GM.MediaContent
    func react(_ request: GM.SendReactionRequest) async throws(LibGMError) -> GM.SendReactionResponse
    func deleteMessage(id: String) async throws(LibGMError) -> GM.DeleteMessageResponse
    func updateConversation(_ request: GM.UpdateConversationRequest) async throws(LibGMError) -> GM.UpdateConversationResponse
    func listContacts() async throws(LibGMError) -> GM.ListContactsResponse
    func getOrCreateConversation(_ request: GM.GetOrCreateConversationRequest) async throws(LibGMError) -> GM.GetOrCreateConversationResponse
}

extension LibGMSession: GoogleMessagesSession {}

/// Builds a session from saved credentials (nil for a fresh pairing).
public typealias GoogleMessagesSessionFactory = @Sendable (_ savedSession: Data?) throws(LibGMError) -> any GoogleMessagesSession
