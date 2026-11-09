import Foundation
@testable import LibGMAdapter
import LibGMKit
import Synchronization

/// Stands in for a libgm session: records calls, replays scripted events and responses.
final class FakeGoogleMessagesSession: GoogleMessagesSession {
    let savedSession: Data?
    let events: AsyncStream<LibGMEvent>
    private let continuation: AsyncStream<LibGMEvent>.Continuation
    private let log = Mutex<[String]>([])
    private let sent = Mutex<[GM.SendMessageRequest]>([])
    private let sendFailure = Mutex<LibGMError?>(nil)
    private let uploadFailure = Mutex<LibGMError?>(nil)
    private let heldFetches = Mutex<AsyncStream<Void>?>(nil)
    private let page = Mutex(GM.ListMessagesResponse())
    private let thumbnails = Mutex(GM.GetThumbnailResponse())
    private let addressBook = Mutex(GM.ListContactsResponse())
    private let created = Mutex(GM.GetOrCreateConversationResponse())
    private let inbox = Mutex<Result<GM.ListConversationsResponse, LibGMError>>(.success(GM.ListConversationsResponse()))

    init(savedSession: Data?) {
        self.savedSession = savedSession
        (events, continuation) = AsyncStream.makeStream(of: LibGMEvent.self)
    }

    var calls: [String] { log.withLock { $0 } }
    var sentRequests: [GM.SendMessageRequest] { sent.withLock { $0 } }

    func emit(_ event: LibGMEvent) { continuation.yield(event) }
    /// Fetches then wait, as if for a phone, until the returned continuation is told to go.
    func holdFetches() -> AsyncStream<Void>.Continuation {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        heldFetches.withLock { $0 = stream }
        return continuation
    }

    func stubPage(_ response: GM.ListMessagesResponse) { page.withLock { $0 = response } }
    func stubThumbnails(_ response: GM.GetThumbnailResponse) { thumbnails.withLock { $0 = response } }
    func stubContacts(_ response: GM.ListContactsResponse) { addressBook.withLock { $0 = response } }
    func stubCreatedConversation(_ response: GM.GetOrCreateConversationResponse) { created.withLock { $0 = response } }
    func stubSend(_ error: LibGMError) { sendFailure.withLock { $0 = error } }
    func stubUpload(_ error: LibGMError) { uploadFailure.withLock { $0 = error } }
    func stubInbox(_ result: Result<GM.ListConversationsResponse, LibGMError>) { inbox.withLock { $0 = result } }

    func startGoogleAccountPairing(cookies: [String: String]) async throws(LibGMError) {
        record("googlePairing:" + cookies.keys.sorted().joined(separator: ","))
    }
    func connect() async throws(LibGMError) { record("connect") }
    func disconnect() async { record("disconnect") }
    func unpair() async throws(LibGMError) { record("unpair") }
    func close() {
        record("close")
        continuation.finish()
    }

    func listConversations(_ request: GM.ListConversationsRequest) async throws(LibGMError) -> GM.ListConversationsResponse {
        record("list:\(request.folder):\(request.count)")
        return try inbox.withLock { $0 }.get()
    }

    func fetchMessages(conversationID: String, count: Int64, before cursor: GM.Cursor?) async throws(LibGMError) -> GM.ListMessagesResponse {
        record("fetch:\(conversationID):\(count):\(cursor?.lastItemID ?? "-")")
        if let held = heldFetches.withLock({ $0 }) {
            for await _ in held { break }
        }
        return page.withLock { $0 }
    }

    func downloadMedia(id: String, key: Data) async throws(LibGMError) -> Data {
        record("download:\(id):\(String(decoding: key, as: UTF8.self))")
        return Data("contents".utf8)
    }

    func participantThumbnails(ids: [String]) async throws(LibGMError) -> GM.GetThumbnailResponse {
        record("thumbnails:" + ids.sorted().joined(separator: ","))
        return thumbnails.withLock { $0 }
    }

    func uploadMedia(data: Data, fileName: String, mimeType: String) async throws(LibGMError) -> GM.MediaContent {
        record("upload:\(fileName):\(mimeType)")
        if let failure = uploadFailure.withLock({ $0 }) { throw failure }
        return .with { $0.mediaID = "uploaded-\(fileName)" }
    }

    private let updates = Mutex<[GM.UpdateConversationRequest]>([])
    private let reactions = Mutex<[GM.SendReactionRequest]>([])
    var updateRequests: [GM.UpdateConversationRequest] { updates.withLock { $0 } }
    var reactionRequests: [GM.SendReactionRequest] { reactions.withLock { $0 } }

    func react(_ request: GM.SendReactionRequest) async throws(LibGMError) -> GM.SendReactionResponse {
        reactions.withLock { $0.append(request) }
        return .with { $0.success = true }
    }

    func deleteMessage(id: String) async throws(LibGMError) -> GM.DeleteMessageResponse {
        record("deleteMessage:\(id)")
        return .with { $0.success = true }
    }

    func updateConversation(_ request: GM.UpdateConversationRequest) async throws(LibGMError) -> GM.UpdateConversationResponse {
        updates.withLock { $0.append(request) }
        return .with { $0.success = true }
    }

    func listContacts() async throws(LibGMError) -> GM.ListContactsResponse {
        record("contacts")
        return addressBook.withLock { $0 }
    }

    func getOrCreateConversation(_ request: GM.GetOrCreateConversationRequest) async throws(LibGMError) -> GM.GetOrCreateConversationResponse {
        record("getOrCreate:" + request.numbers.map(\.number).joined(separator: ","))
        return created.withLock { $0 }
    }

    func send(_ request: GM.SendMessageRequest) async throws(LibGMError) -> GM.SendMessageResponse {
        sent.withLock { $0.append(request) }
        if let failure = sendFailure.withLock({ $0 }) { throw failure }
        return GM.SendMessageResponse()
    }

    func markRead(conversationID: String, messageID: String) async throws(LibGMError) {
        record("markRead:\(conversationID):\(messageID)")
    }

    private func record(_ entry: String) { log.withLock { $0.append(entry) } }
}

/// Hands out fake sessions and remembers them, newest last.
final class FakeSessionFactory: Sendable {
    private let made = Mutex<[FakeGoogleMessagesSession]>([])

    var sessions: [FakeGoogleMessagesSession] { made.withLock { $0 } }
    var latest: FakeGoogleMessagesSession? { sessions.last }

    var factory: GoogleMessagesSessionFactory {
        { savedSession throws(LibGMError) in
            let session = FakeGoogleMessagesSession(savedSession: savedSession)
            self.made.withLock { $0.append(session) }
            return session
        }
    }
}
