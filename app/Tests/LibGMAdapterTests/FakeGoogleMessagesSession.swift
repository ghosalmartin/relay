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
    private let page = Mutex(GM.ListMessagesResponse())
    private let thumbnails = Mutex(GM.GetThumbnailResponse())
    private let inbox = Mutex<Result<GM.ListConversationsResponse, LibGMError>>(.success(GM.ListConversationsResponse()))

    init(savedSession: Data?) {
        self.savedSession = savedSession
        (events, continuation) = AsyncStream.makeStream(of: LibGMEvent.self)
    }

    var calls: [String] { log.withLock { $0 } }
    var sentRequests: [GM.SendMessageRequest] { sent.withLock { $0 } }

    func emit(_ event: LibGMEvent) { continuation.yield(event) }
    func stubPage(_ response: GM.ListMessagesResponse) { page.withLock { $0 = response } }
    func stubThumbnails(_ response: GM.GetThumbnailResponse) { thumbnails.withLock { $0 = response } }
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

    func send(_ request: GM.SendMessageRequest) async throws(LibGMError) -> GM.SendMessageResponse {
        sent.withLock { $0.append(request) }
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
