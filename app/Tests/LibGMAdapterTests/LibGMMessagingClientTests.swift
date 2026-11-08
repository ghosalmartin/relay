import Foundation
@testable import LibGMAdapter
import LibGMKit
import MessagingDomain
import MessagingTestSupport
import Testing

@Suite struct LibGMMessagingClientTests {
    @Test func pairingThenReconnectsWithTheNewCredentials() async throws {
        let sessions = FakeSessionFactory()
        let client = LibGMMessagingClient(makeSession: sessions.factory)
        let events = client.events()

        try await client.startPairing()
        let pairing = try #require(sessions.latest)
        pairing.emit(.qrCode("qr"))
        pairing.emit(.sessionUpdated(Data("creds".utf8)))
        pairing.emit(.paired(phoneID: "phone"))

        #expect(await events.first(3) == [.pairingCode("qr"), .sessionChanged(SessionData(bytes: Data("creds".utf8))), .paired])
        #expect(await eventually { sessions.sessions.count == 2 })
        let connected = try #require(sessions.latest)
        #expect(connected.savedSession == Data("creds".utf8))
        #expect(await eventually { connected.calls == ["connect"] })
        #expect(pairing.calls.contains("close"))
    }

    @Test func sendingUsesTheRememberedConversation() async throws {
        let sessions = FakeSessionFactory()
        let client = LibGMMessagingClient(makeSession: sessions.factory)
        let events = client.events()
        try await client.connect(using: Fixtures.session)
        let session = try #require(sessions.latest)

        session.emit(.conversation(ProtoFixtures.conversation("c1", outgoingID: "me-7")))
        _ = await events.first(1)
        try await client.sendText("hello", to: ConversationID("c1"))

        let request = try #require(session.sentRequests.first)
        #expect(request.messagePayload.participantID == "me-7")
    }

    @Test func sendingToAnUnknownConversationFails() async throws {
        let sessions = FakeSessionFactory()
        let client = LibGMMessagingClient(makeSession: sessions.factory)
        try await client.connect(using: Fixtures.session)

        await #expect(throws: MessagingError.conversationNotFound(ConversationID("nope"))) {
            try await client.sendText("hi", to: ConversationID("nope"))
        }
    }

    @Test func callsBeforeConnectingSayNotPaired() async {
        let client = LibGMMessagingClient(makeSession: FakeSessionFactory().factory)

        await #expect(throws: MessagingError.notPaired) {
            try await client.markRead(ConversationID("c1"), upTo: MessageID("m1"))
        }
    }

    @Test func historyComesBackOldestFirstWithACursor() async throws {
        let sessions = FakeSessionFactory()
        let client = LibGMMessagingClient(makeSession: sessions.factory)
        try await client.connect(using: Fixtures.session)
        let response = GM.ListMessagesResponse.with {
            $0.messages = [
                ProtoFixtures.message("new", micros: 2_000_000),
                ProtoFixtures.message("notice", status: .tombstoneParticipantJoined),
                ProtoFixtures.message("old", micros: 1_000_000),
            ]
            $0.cursor.lastItemID = "old"
            $0.cursor.lastItemTimestamp = 1_000_000
        }
        try #require(sessions.latest).stubPage(response)

        let page = try await client.messages(in: ConversationID("c1"), before: nil, limit: 30)

        #expect(page.messages.map(\.id.rawValue) == ["old", "new"])
        #expect(page.olderCursor != nil)
        #expect(sessions.latest?.calls.last == "fetch:c1:30:-")
    }

    @Test func unpairingTellsSubscribersTheSessionIsOver() async throws {
        let sessions = FakeSessionFactory()
        let client = LibGMMessagingClient(makeSession: sessions.factory)
        try await client.connect(using: Fixtures.session)
        let events = client.events()

        try await client.unpair()

        #expect(await events.first(1) == [.loggedOut])
    }

    @Test func unpairingEndsTheSession() async throws {
        let sessions = FakeSessionFactory()
        let client = LibGMMessagingClient(makeSession: sessions.factory)
        try await client.connect(using: Fixtures.session)

        try await client.unpair()

        #expect(sessions.latest?.calls.suffix(2) == ["unpair", "close"])
        await #expect(throws: MessagingError.notPaired) { try await client.refreshPairingCode() }
    }
}
