import Foundation
@testable import LibGMAdapter
import LibGMKit
import MessagingDomain
import MessagingTestSupport
import Testing

@Suite struct LibGMMessagingClientTests {
    @Test func pairingUsesTheCookiesAndKeepsTheSameSession() async throws {
        let sessions = FakeSessionFactory()
        let client = LibGMMessagingClient(makeSession: sessions.factory)
        let events = client.events()

        try await client.startPairing(with: Fixtures.accountCookies)
        let pairing = try #require(sessions.latest)
        pairing.emit(.googleAccountEmoji("🦊"))
        pairing.emit(.sessionUpdated(Data("creds".utf8)))
        pairing.emit(.paired(phoneID: "phone"))

        #expect(await events.first(3) == [.pairingConfirmationEmoji("🦊"), .sessionChanged(SessionData(bytes: Data("creds".utf8))), .paired])
        // libgm reconnects by itself after Google account pairing; a second session would fight it.
        #expect(sessions.sessions.count == 1)
        #expect(pairing.calls == ["googlePairing:SID"])
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

    @Test func thePhonesFirstSettingsLoadTheInboxOnceAndConversationsCanBeSentTo() async throws {
        let sessions = FakeSessionFactory()
        let client = LibGMMessagingClient(makeSession: sessions.factory)
        let events = client.events()
        try await client.connect(using: Fixtures.session)
        let session = try #require(sessions.latest)
        session.stubInbox(.success(.with { $0.conversations = [ProtoFixtures.conversation("c1", outgoingID: "me-7")] }))

        session.emit(.settings(GM.Settings()))
        session.emit(.settings(GM.Settings()))
        session.emit(.connectionRecovered)     // the pump has handled both settings once this arrives
        let received = await events.first(3)

        #expect(received.contains(.initialSyncCompleted))
        #expect(session.calls == ["connect", "list:inbox:50"])
        try await client.sendText("hello", to: ConversationID("c1"))
        #expect(session.sentRequests.count == 1)
    }

    @Test func aFailedInboxLoadIsReportedAndRetriedOnTheNextSettings() async throws {
        let sessions = FakeSessionFactory()
        let client = LibGMMessagingClient(makeSession: sessions.factory)
        let events = client.events()
        try await client.connect(using: Fixtures.session)
        let session = try #require(sessions.latest)
        session.stubInbox(.failure(.bridge("no answer")))

        session.emit(.settings(GM.Settings()))
        #expect(await events.first(1) == [.connectionInterrupted(reason: "Couldn't load your conversations.")])

        session.stubInbox(.success(GM.ListConversationsResponse()))
        session.emit(.settings(GM.Settings()))
        #expect(await events.first(1) == [.initialSyncCompleted])
    }

    @Test func downloadingAnAttachmentUsesItsKey() async throws {
        let sessions = FakeSessionFactory()
        let client = LibGMMessagingClient(makeSession: sessions.factory)
        try await client.connect(using: Fixtures.session)
        let attachment = Attachment(id: "m1", fileName: "", mimeType: "image/png", byteCount: nil, accessKey: Data("secret".utf8))

        let data = try await client.attachmentData(attachment)

        #expect(data == Data("contents".utf8))
        #expect(sessions.latest?.calls.last == "download:m1:secret")
    }

    @Test func anEmbeddedAttachmentNeedsNoDownload() async throws {
        let sessions = FakeSessionFactory()
        let client = LibGMMessagingClient(makeSession: sessions.factory)
        try await client.connect(using: Fixtures.session)
        let attachment = Attachment(id: "inline", fileName: "", mimeType: "image/png", byteCount: nil, inlineData: Data("embedded".utf8))

        let data = try await client.attachmentData(attachment)

        #expect(data == Data("embedded".utf8))
        #expect(sessions.latest?.calls == ["connect"])
    }

    @Test func avatarsMatchTheirPeopleAndEmptyPhotosAreLeftOut() async throws {
        let sessions = FakeSessionFactory()
        let client = LibGMMessagingClient(makeSession: sessions.factory)
        try await client.connect(using: Fixtures.session)
        try #require(sessions.latest).stubThumbnails(.with {
            $0.thumbnail = [
                .with { $0.identifier = "p1"; $0.data.imageBuffer = Data("photo".utf8) },
                .with { $0.identifier = "p2" },
            ]
        })

        let avatars = try await client.avatars(for: [ParticipantID("p1"), ParticipantID("p2")])

        #expect(avatars == [ParticipantID("p1"): Data("photo".utf8)])
        #expect(sessions.latest?.calls.last == "thumbnails:p1,p2")
    }

    @Test func anAttachmentIsUploadedThenSentWithItsCaption() async throws {
        let sessions = FakeSessionFactory()
        let client = LibGMMessagingClient(makeSession: sessions.factory)
        let events = client.events()
        try await client.connect(using: Fixtures.session)
        let session = try #require(sessions.latest)
        session.emit(.conversation(ProtoFixtures.conversation("c1", outgoingID: "me-7")))
        _ = await events.first(1)

        try await client.sendAttachment(
            OutgoingAttachment(data: Data("x".utf8), fileName: "a.png", mimeType: "image/png"),
            caption: "Look",
            to: ConversationID("c1")
        )

        #expect(session.calls.last == "upload:a.png:image/png")
        let parts = try #require(session.sentRequests.first).messagePayload.messageInfo
        #expect(parts.first?.mediaContent.mediaID == "uploaded-a.png")
        #expect(parts.last?.messageContent.content == "Look")
    }

    @Test func anAttachmentForAnUnknownConversationIsNotUploaded() async throws {
        let sessions = FakeSessionFactory()
        let client = LibGMMessagingClient(makeSession: sessions.factory)
        try await client.connect(using: Fixtures.session)

        await #expect(throws: MessagingError.conversationNotFound(ConversationID("nope"))) {
            try await client.sendAttachment(
                OutgoingAttachment(data: Data(), fileName: "a.png", mimeType: "image/png"), caption: nil, to: ConversationID("nope")
            )
        }
        #expect(sessions.latest?.calls == ["connect"])
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
        await #expect(throws: MessagingError.notPaired) { try await client.markRead(ConversationID("c1"), upTo: MessageID("m1")) }
    }
}
