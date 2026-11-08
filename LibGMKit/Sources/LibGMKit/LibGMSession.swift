import Foundation
import SwiftProtobuf

/// One connection to Google Messages for web, backed by libgm.
///
/// Lifecycle: create with a saved session (or none), then either `startQRPairing()`
/// or `connect()`. Persist every `.sessionUpdated` payload. Call `close()` when done.
///
/// `events` is a single stream: iterate it from one place and fan out from there.
/// All methods suspend while libgm does network I/O; none block the caller's thread.
public final class LibGMSession: Sendable {
    public let events: AsyncStream<LibGMEvent>
    private let bridge: any NativeBridge

    /// - Parameter savedSession: the latest `.sessionUpdated` payload, or nil to pair fresh.
    public convenience init(savedSession: Data?) throws(LibGMError) {
        self.init(bridge: try CBridge(savedSession: savedSession))
    }

    init(bridge: any NativeBridge) {
        self.bridge = bridge
        self.events = AsyncStream { continuation in
            let task = Task {
                for await raw in bridge.rawEvents {
                    if let event = LibGMEvent(kind: raw.kind, payload: raw.payload) {
                        continuation.yield(event)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Pairing and connection

    /// Emits `.qrCode`. Codes expire after about 30 seconds; call `refreshQRCode()`.
    public func startQRPairing() async throws(LibGMError) {
        try await offThread { bridge throws(LibGMError) in try bridge.startQRPairing() }
    }

    public func refreshQRCode() async throws(LibGMError) {
        try await offThread { bridge throws(LibGMError) in try bridge.refreshQRCode() }
    }

    /// Pairs through a Google account. `cookies` come from signing in to messages.google.com
    /// in a web view. Emits `.googleAccountEmoji` for the user to confirm on their phone.
    public func startGoogleAccountPairing(cookies: [String: String]) async throws(LibGMError) {
        let body = try encodeJSON(cookies)
        try await offThread { bridge throws(LibGMError) in try bridge.startGoogleAccountPairing(cookiesJSON: body) }
    }

    public func connect() async throws(LibGMError) {
        try await offThread { bridge throws(LibGMError) in try bridge.connect() }
    }

    public func disconnect() async {
        await offThread { bridge in bridge.disconnect() }
    }

    /// Revokes this device on the phone.
    public func unpair() async throws(LibGMError) {
        try await offThread { bridge throws(LibGMError) in try bridge.unpair() }
    }

    /// Stops libgm and ends `events`. The session cannot be used afterwards.
    public func close() {
        bridge.close()
    }

    // MARK: Conversations and messages

    public func listConversations(_ request: GM.ListConversationsRequest) async throws(LibGMError) -> GM.ListConversationsResponse {
        try await call(.listConversations, protobuf: request)
    }

    /// Fetches up to `count` messages before `cursor` (newest page when nil).
    public func fetchMessages(conversationID: String, count: Int64, before cursor: GM.Cursor? = nil) async throws(LibGMError) -> GM.ListMessagesResponse {
        try await call(.fetchMessages, json: BridgeRequest.FetchMessages(
            conversation_id: conversationID,
            count: count,
            cursor_id: cursor?.lastItemID,
            cursor_timestamp: cursor?.lastItemTimestamp
        ))
    }

    public func conversation(id: String) async throws(LibGMError) -> GM.Conversation {
        try await call(.getConversation, json: BridgeRequest.Conversation(conversation_id: id))
    }

    public func send(_ request: GM.SendMessageRequest) async throws(LibGMError) -> GM.SendMessageResponse {
        try await call(.sendMessage, protobuf: request)
    }

    public func react(_ request: GM.SendReactionRequest) async throws(LibGMError) -> GM.SendReactionResponse {
        try await call(.sendReaction, protobuf: request)
    }

    public func markRead(conversationID: String, messageID: String) async throws(LibGMError) {
        _ = try await raw(.markRead, encodeJSON(BridgeRequest.MarkRead(conversation_id: conversationID, message_id: messageID)))
    }

    public func deleteMessage(id: String) async throws(LibGMError) -> GM.DeleteMessageResponse {
        try await call(.deleteMessage, json: BridgeRequest.Message(message_id: id))
    }

    public func getOrCreateConversation(_ request: GM.GetOrCreateConversationRequest) async throws(LibGMError) -> GM.GetOrCreateConversationResponse {
        try await call(.getOrCreateConversation, protobuf: request)
    }

    public func updateConversation(_ request: GM.UpdateConversationRequest) async throws(LibGMError) -> GM.UpdateConversationResponse {
        try await call(.updateConversation, protobuf: request)
    }

    // MARK: Contacts and media

    public func listContacts() async throws(LibGMError) -> GM.ListContactsResponse {
        try await call(.listContacts, request: Data())
    }

    public func participantThumbnails(ids: [String]) async throws(LibGMError) -> GM.GetThumbnailResponse {
        try await call(.participantThumbnails, json: BridgeRequest.IDs(ids: ids))
    }

    public func fullSizeImage(messageID: String, actionMessageID: String) async throws(LibGMError) -> GM.GetFullSizeImageResponse {
        try await call(.fullSizeImage, json: BridgeRequest.FullSizeImage(message_id: messageID, action_message_id: actionMessageID))
    }

    /// Downloads and decrypts a message attachment.
    public func downloadMedia(id: String, key: Data) async throws(LibGMError) -> Data {
        let response: Google_Protobuf_BytesValue = try await call(.downloadMedia, json: BridgeRequest.DownloadMedia(media_id: id, key: key))
        return response.value
    }

    // MARK: Plumbing

    private func call<Response: SwiftProtobuf.Message>(_ method: BridgeMethod, protobuf request: some SwiftProtobuf.Message) async throws(LibGMError) -> Response {
        let body: Data
        do { body = try request.serializedBytes() } catch { throw .malformed("request: \(error)") }
        return try await call(method, request: body)
    }

    private func call<Response: SwiftProtobuf.Message>(_ method: BridgeMethod, json request: some Encodable) async throws(LibGMError) -> Response {
        try await call(method, request: encodeJSON(request))
    }

    private func call<Response: SwiftProtobuf.Message>(_ method: BridgeMethod, request: Data) async throws(LibGMError) -> Response {
        let bytes = try await raw(method, request)
        do { return try Response(serializedBytes: bytes) } catch { throw .malformed("response: \(error)") }
    }

    private func raw(_ method: BridgeMethod, _ request: Data) async throws(LibGMError) -> Data {
        try await offThread { bridge throws(LibGMError) in try bridge.call(method, request: request) }
    }

    private func encodeJSON(_ value: some Encodable) throws(LibGMError) -> Data {
        do { return try JSONEncoder().encode(value) } catch { throw .malformed("request: \(error)") }
    }

    /// Runs a blocking bridge call on a background thread, keeping Swift's cooperative pool free.
    private func offThread<T: Sendable>(_ work: @escaping @Sendable (any NativeBridge) throws(LibGMError) -> T) async throws(LibGMError) -> T {
        let bridge = self.bridge
        let result: Result<T, LibGMError> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do throws(LibGMError) {
                    continuation.resume(returning: .success(try work(bridge)))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
        return try result.get()
    }

    private func offThread(_ work: @escaping @Sendable (any NativeBridge) -> Void) async {
        _ = try? await offThread { bridge throws(LibGMError) in work(bridge) }
    }
}
