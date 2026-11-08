import Foundation
@testable import LibGMKit
import SwiftProtobuf
import Testing

@Suite struct LibGMSessionTests {
    @Test func forwardsDecodedEventsAndSkipsUnknownOnes() async {
        let bridge = FakeNativeBridge()
        let session = LibGMSession(bridge: bridge)

        bridge.emit(kind: 999)
        bridge.emit(kind: BridgeEventKind.qrCode.rawValue, payload: Data("qr".utf8))
        bridge.emit(kind: BridgeEventKind.loggedOut.rawValue)
        session.close()

        var events: [LibGMEvent] = []
        for await event in session.events { events.append(event) }
        #expect(events == [.qrCode("qr"), .loggedOut])
    }

    @Test func fetchMessagesSendsCursorFields() async throws {
        let bridge = FakeNativeBridge()
        let session = LibGMSession(bridge: bridge)
        var cursor = GM.Cursor()
        cursor.lastItemID = "m9"
        cursor.lastItemTimestamp = 42

        _ = try await session.fetchMessages(conversationID: "c1", count: 30, before: cursor)

        let call = try #require(bridge.calls.first)
        #expect(call.hasPrefix("call:fetchMessages:"))
        #expect(call.contains(#""cursor_id":"m9""#))
        #expect(call.contains(#""cursor_timestamp":42"#))
    }

    @Test func decodesProtobufResponses() async throws {
        let bridge = FakeNativeBridge()
        var expected = GM.Conversation()
        expected.name = "Sam"
        bridge.respond(to: .getConversation, with: .success(try expected.serializedBytes()))

        let conversation = try await LibGMSession(bridge: bridge).conversation(id: "c1")

        #expect(conversation.name == "Sam")
    }

    @Test func surfacesBridgeErrors() async {
        let bridge = FakeNativeBridge()
        bridge.respond(to: .markRead, with: .failure(.bridge("phone offline")))

        await #expect(throws: LibGMError.bridge("phone offline")) {
            try await LibGMSession(bridge: bridge).markRead(conversationID: "c1", messageID: "m1")
        }
    }

    @Test func rejectsUndecodableResponses() async {
        let bridge = FakeNativeBridge()
        bridge.respond(to: .getConversation, with: .success(Data([0xFF, 0xFF])))

        await #expect {
            _ = try await LibGMSession(bridge: bridge).conversation(id: "c1")
        } throws: { error in
            if case LibGMError.malformed = error { return true }
            return false
        }
    }

    @Test func googlePairingSendsCookiesAsJSON() async throws {
        let bridge = FakeNativeBridge()

        try await LibGMSession(bridge: bridge).startGoogleAccountPairing(cookies: ["SID": "abc"])

        #expect(bridge.calls == [#"google:{"SID":"abc"}"#])
    }
}
