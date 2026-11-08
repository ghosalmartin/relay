import Foundation
import GMBridgeC
import SwiftProtobuf

/// Event kinds emitted by the Go bridge. Mirrors the ev* constants in bridge/bridge.go.
public enum GMEventKind: Int32, Sendable {
    case qr = 1, pairSuccess, authUpdated, ready, conversation, message, messageOld,
         typing, settings, phoneNotResponding, phoneRespondingAgain, fatal,
         temporaryError, recovered, loggedOut, gaiaEmoji
}

/// Method ids for `gm_call`. Mirrors the m* constants in bridge/bridge.go.
enum GMMethod: Int32 {
    case listConversations = 1, fetchMessages, sendMessage, sendReaction, markRead,
         listContacts, getOrCreateConversation, participantThumbnails, fullSizeImage,
         deleteMessage, getConversation, updateConversation
}

public enum GMEvent: Sendable {
    case qr(url: String)
    case gaiaEmoji(String)
    case pairSuccess(phoneID: String)
    case authUpdated(Data)              // persist to Keychain verbatim
    case ready
    case conversation(GM.Conversation)
    case message(GM.Message, isOld: Bool)
    case typing(GM.TypingData)
    case settings(GM.Settings)
    case phoneNotResponding, phoneRespondingAgain, recovered, loggedOut
    case temporaryError(String)
    case fatal(String)
}

public struct GMError: Error, CustomStringConvertible {
    public let description: String
}

/// Thin, thread-safe wrapper over one libgm session. All calls block, so they are
/// `nonisolated async` and hop off the caller's actor via a detached task.
public final class GMSession: @unchecked Sendable {
    private var handle: Int64 = 0
    private let continuation: AsyncStream<GMEvent>.Continuation
    public let events: AsyncStream<GMEvent>

    /// - Parameter auth: saved auth JSON from a previous `.authUpdated`, or nil to pair fresh.
    public init(auth: Data?) throws {
        (events, continuation) = AsyncStream.makeStream(of: GMEvent.self, bufferingPolicy: .unbounded)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let h: Int64 = auth.map { data in
            data.withUnsafeBytes { raw in
                gm_session_new(UnsafeMutablePointer(mutating: raw.bindMemory(to: UInt8.self).baseAddress),
                               Int64(data.count), gmEventTrampoline, ctx)
            }
        } ?? gm_session_new(nil, 0, gmEventTrampoline, ctx)
        guard h > 0 else { throw GMError(description: "Could not create session (bad auth data?)") }
        handle = h
    }

    deinit {
        gm_session_free(handle)
        continuation.finish()
    }

    // MARK: Lifecycle

    public func startQRPairing() async throws { try await run { gm_start_qr_pairing(self.handle, $0, $1) } }
    public func refreshQR() async throws { try await run { gm_refresh_qr(self.handle, $0, $1) } }
    public func connect() async throws { try await run { gm_connect(self.handle, $0, $1) } }
    public func unpair() async throws { try await run { gm_unpair(self.handle, $0, $1) } }
    public func disconnect() { gm_disconnect(handle) }

    public func startGooglePairing(cookies: [String: String]) async throws {
        let json = try JSONEncoder().encode(cookies)
        try await run { out, len in
            json.withUnsafeBytes { raw in
                gm_set_cookies(self.handle, UnsafeMutablePointer(mutating: raw.bindMemory(to: UInt8.self).baseAddress),
                               Int64(json.count), out, len)
            }
        }
        try await run { gm_start_google_pairing(self.handle, $0, $1) }
    }

    // MARK: RPCs

    public func listConversations(_ req: GM.ListConversationsRequest) async throws -> GM.ListConversationsResponse {
        try await call(.listConversations, proto: req)
    }

    public func fetchMessages(conversationID: String, count: Int64 = 30,
                              before cursor: GM.Cursor? = nil) async throws -> GM.ListMessagesResponse {
        struct Req: Encodable { let conversation_id: String; let count: Int64; let cursor_id: String; let cursor_ts: Int64 }
        let r = Req(conversation_id: conversationID, count: count,
                    cursor_id: cursor?.lastItemID ?? "", cursor_ts: cursor?.lastItemTimestamp ?? 0)
        return try await call(.fetchMessages, json: r)
    }

    public func send(_ req: GM.SendMessageRequest) async throws -> GM.SendMessageResponse {
        try await call(.sendMessage, proto: req)
    }

    public func react(_ req: GM.SendReactionRequest) async throws -> GM.SendReactionResponse {
        try await call(.sendReaction, proto: req)
    }

    public func markRead(conversationID: String, messageID: String) async throws {
        struct Req: Encodable { let conversation_id: String; let message_id: String }
        _ = try await raw(.markRead, try JSONEncoder().encode(Req(conversation_id: conversationID, message_id: messageID)))
    }

    public func listContacts() async throws -> GM.ListContactsResponse {
        try await call(.listContacts, input: Data())
    }

    public func participantThumbnails(_ ids: [String]) async throws -> GM.GetThumbnailResponse {
        struct Req: Encodable { let ids: [String] }
        return try await call(.participantThumbnails, json: Req(ids: ids))
    }

    // MARK: Plumbing

    private func call<R: SwiftProtobuf.Message>(_ m: GMMethod, proto req: some SwiftProtobuf.Message) async throws -> R {
        try await call(m, input: try req.serializedData())
    }

    private func call<R: SwiftProtobuf.Message>(_ m: GMMethod, json req: some Encodable) async throws -> R {
        try await call(m, input: try JSONEncoder().encode(req))
    }

    private func call<R: SwiftProtobuf.Message>(_ m: GMMethod, input: Data) async throws -> R {
        try R(serializedBytes: try await raw(m, input))
    }

    private func raw(_ m: GMMethod, _ input: Data) async throws -> Data {
        try await run { out, len in
            input.withUnsafeBytes { raw in
                gm_call(self.handle, m.rawValue,
                        UnsafeMutablePointer(mutating: raw.bindMemory(to: UInt8.self).baseAddress),
                        Int64(input.count), out, len)
            }
        }
    }

    /// Runs a blocking bridge call off the cooperative pool and converts the out-buffer.
    @discardableResult
    private func run(_ body: @escaping @Sendable (UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>,
                                                  UnsafeMutablePointer<Int64>) -> Int32) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var out: UnsafeMutablePointer<UInt8>? = nil
                var len: Int64 = 0
                let rc = body(&out, &len)
                let data = out.map { Data(bytes: $0, count: Int(len)) } ?? Data()
                if let out { gm_free(out) }
                if rc == 0 {
                    cont.resume(returning: data)
                } else {
                    cont.resume(throwing: GMError(description: String(decoding: data, as: UTF8.self)))
                }
            }
        }
    }

    fileprivate func deliver(kind: Int32, data: Data) {
        guard let k = GMEventKind(rawValue: kind) else { return }
        let text = { String(decoding: data, as: UTF8.self) }
        let event: GMEvent?
        switch k {
        case .qr: event = .qr(url: text())
        case .gaiaEmoji: event = .gaiaEmoji(text())
        case .pairSuccess:
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String]
            event = .pairSuccess(phoneID: obj?["phone_id"] ?? "")
        case .authUpdated: event = .authUpdated(data)
        case .ready: event = .ready
        case .conversation: event = (try? GM.Conversation(serializedBytes: data)).map(GMEvent.conversation)
        case .message: event = (try? GM.Message(serializedBytes: data)).map { .message($0, isOld: false) }
        case .messageOld: event = (try? GM.Message(serializedBytes: data)).map { .message($0, isOld: true) }
        case .typing: event = (try? GM.TypingData(serializedBytes: data)).map(GMEvent.typing)
        case .settings: event = (try? GM.Settings(serializedBytes: data)).map(GMEvent.settings)
        case .phoneNotResponding: event = .phoneNotResponding
        case .phoneRespondingAgain: event = .phoneRespondingAgain
        case .fatal: event = .fatal(text())
        case .temporaryError: event = .temporaryError(text())
        case .recovered: event = .recovered
        case .loggedOut: event = .loggedOut
        }
        if let event { continuation.yield(event) }
    }
}

/// C callback. Runs on a Go thread; copies the bytes and hands them to the session.
private let gmEventTrampoline: gm_event_cb = { ctx, kind, data, len in
    guard let ctx else { return }
    let session = Unmanaged<GMSession>.fromOpaque(ctx).takeUnretainedValue()
    let bytes = (data != nil && len > 0) ? Data(bytes: data!, count: Int(len)) : Data()
    session.deliver(kind: kind, data: bytes)
}
