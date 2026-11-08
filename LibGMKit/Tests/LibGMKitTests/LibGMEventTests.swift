import Foundation
@testable import LibGMKit
import SwiftProtobuf
import Testing

@Suite struct LibGMEventTests {
    @Test func decodesProtobufPayloads() throws {
        let conversation = GM.Conversation.with { $0.conversationID = "c1" }

        let event = LibGMEvent(kind: BridgeEventKind.conversation.rawValue, payload: try conversation.serializedBytes())

        #expect(event == .conversation(conversation))
    }

    @Test func historicalMessagesAreFlagged() throws {
        let message = GM.Message.with { $0.messageID = "m1" }
        let bytes: Data = try message.serializedBytes()

        #expect(LibGMEvent(kind: BridgeEventKind.message.rawValue, payload: bytes) == .message(message, isHistorical: false))
        #expect(LibGMEvent(kind: BridgeEventKind.historicalMessage.rawValue, payload: bytes) == .message(message, isHistorical: true))
    }

    @Test func decodesTextAndJSONPayloads() {
        #expect(LibGMEvent(kind: 1, payload: Data("https://qr".utf8)) == .qrCode("https://qr"))
        #expect(LibGMEvent(kind: 2, payload: Data(#"{"phone_id":"p1"}"#.utf8)) == .paired(phoneID: "p1"))
        #expect(LibGMEvent(kind: 12, payload: Data("revoked".utf8)) == .fatalError("revoked"))
    }

    @Test func mapsReachabilityToOneCase() {
        #expect(LibGMEvent(kind: 10, payload: Data()) == .phoneReachable(false))
        #expect(LibGMEvent(kind: 11, payload: Data()) == .phoneReachable(true))
    }

    @Test func ignoresUnknownKindsAndGarbage() {
        #expect(LibGMEvent(kind: 999, payload: Data()) == nil)
        #expect(LibGMEvent(kind: BridgeEventKind.conversation.rawValue, payload: Data([0xFF, 0xFF])) == nil)
        #expect(LibGMEvent(kind: BridgeEventKind.paired.rawValue, payload: Data("not json".utf8)) == nil)
    }

    @Test func everyKindIsHandled() {
        for kind in BridgeEventKind.allCases where kind.carriesPlainPayload {
            #expect(LibGMEvent(kind: kind.rawValue, payload: Data()) != nil, "kind \(kind)")
        }
    }
}

private extension BridgeEventKind {
    /// Kinds that decode from an empty payload (no protobuf or JSON body required).
    var carriesPlainPayload: Bool {
        switch self {
        case .paired: false
        default: true   // empty bytes are a valid empty protobuf message too
        }
    }
}
