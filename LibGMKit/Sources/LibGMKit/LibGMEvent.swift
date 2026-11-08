import Foundation
import SwiftProtobuf

/// Everything libgm tells the host app, with libgm's own protobuf types as payloads.
public enum LibGMEvent: Sendable, Equatable {
    /// Render as a QR code for the phone to scan. Replaces any earlier code.
    case qrCode(String)
    /// Show this emoji; the user taps the same one on their phone (Google-account pairing).
    case googleAccountEmoji(String)
    case paired(phoneID: String)
    /// Persist these bytes and pass them to `LibGMSession(savedSession:)` next launch.
    case sessionUpdated(Data)
    case initialSyncDone
    case conversation(GM.Conversation)
    case message(GM.Message, isHistorical: Bool)
    case typing(GM.TypingData)
    case settings(GM.Settings)
    case phoneReachable(Bool)
    case transientError(String)
    case connectionRecovered
    case fatalError(String)
    case loggedOut

    /// Decodes one raw bridge event. Nil for unknown kinds or undecodable payloads,
    /// so a newer bridge can add events without breaking an older app.
    init?(kind: Int32, payload: Data) {
        guard let kind = BridgeEventKind(rawValue: kind) else { return nil }
        let text = String(decoding: payload, as: UTF8.self)
        switch kind {
        case .qrCode: self = .qrCode(text)
        case .googleAccountEmoji: self = .googleAccountEmoji(text)
        case .paired:
            guard let body = try? JSONDecoder().decode([String: String].self, from: payload) else { return nil }
            self = .paired(phoneID: body["phone_id"] ?? "")
        case .sessionUpdated: self = .sessionUpdated(payload)
        case .initialSyncDone: self = .initialSyncDone
        case .conversation:
            guard let value = Self.decode(GM.Conversation.self, payload) else { return nil }
            self = .conversation(value)
        case .message, .historicalMessage:
            guard let value = Self.decode(GM.Message.self, payload) else { return nil }
            self = .message(value, isHistorical: kind == .historicalMessage)
        case .typing:
            guard let value = Self.decode(GM.TypingData.self, payload) else { return nil }
            self = .typing(value)
        case .settings:
            guard let value = Self.decode(GM.Settings.self, payload) else { return nil }
            self = .settings(value)
        case .phoneUnreachable: self = .phoneReachable(false)
        case .phoneReachable: self = .phoneReachable(true)
        case .transientError: self = .transientError(text)
        case .connectionRecovered: self = .connectionRecovered
        case .fatalError: self = .fatalError(text)
        case .loggedOut: self = .loggedOut
        }
    }

    private static func decode<M: SwiftProtobuf.Message>(_ type: M.Type, _ payload: Data) -> M? {
        try? M(serializedBytes: payload)
    }
}
