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

        let events = await session.events.reduce([LibGMEvent]()) { $0 + [$1] }
        #expect(events == [.qrCode("qr"), .loggedOut])
    }

    @Test func fetchMessagesSendsCursorFields() async throws {
        let bridge = FakeNativeBridge()
        let session = LibGMSession(bridge: bridge)
        let cursor = GM.Cursor.with {
            $0.lastItemID = "m9"
            $0.lastItemTimestamp = 42
        }

        _ = try await session.fetchMessages(conversationID: "c1", count: 30, before: cursor)

        let call = try #require(bridge.calls.first)
        #expect(call.hasPrefix("call:fetchMessages:"))
        #expect(call.contains(#""cursor_id":"m9""#))
        #expect(call.contains(#""cursor_timestamp":42"#))
    }

    @Test func downloadsMediaAsRawBytesWithABase64Key() async throws {
        let bridge = FakeNativeBridge()
        let wrapped = Google_Protobuf_BytesValue.with { $0.value = Data("picture".utf8) }
        bridge.respond(to: .downloadMedia, with: .success(try wrapped.serializedBytes()))

        let data = try await LibGMSession(bridge: bridge).downloadMedia(id: "m1", key: Data("key".utf8))

        #expect(data == Data("picture".utf8))
        let call = try #require(bridge.calls.first)
        #expect(call.contains(#""media_id":"m1""#))
        #expect(call.contains(#""key":"a2V5""#))
    }

    @Test func uploadsMediaWithBase64Data() async throws {
        let bridge = FakeNativeBridge()
        let uploaded = GM.MediaContent.with { $0.mediaID = "m1" }
        bridge.respond(to: .uploadMedia, with: .success(try uploaded.serializedBytes()))

        let media = try await LibGMSession(bridge: bridge).uploadMedia(data: Data("key".utf8), fileName: "a.png", mimeType: "image/png")

        #expect(media.mediaID == "m1")
        let call = try #require(bridge.calls.first)
        #expect(call.contains(#""data":"a2V5""#))
        #expect(call.contains(#""file_name":"a.png""#))
    }

    @Test func decodesProtobufResponses() async throws {
        let bridge = FakeNativeBridge()
        let expected = GM.Conversation.with { $0.name = "Sam" }
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
