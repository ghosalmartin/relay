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

    @Test func contactsWithoutANumberAreLeftOutAndNamelessOnesShowTheirNumber() async throws {
        let sessions = FakeSessionFactory()
        let client = LibGMMessagingClient(makeSession: sessions.factory)
        try await client.connect(using: Fixtures.session)
        try #require(sessions.latest).stubContacts(.with {
            $0.contacts = [
                .with { $0.name = "Sam"; $0.number = .with { $0.number = "+441"; $0.number2 = "+441"; $0.formattedNumber = "01 1" } },
                .with { $0.number = .with { $0.number = "+442" } },
                .with { $0.name = "No Number" },
            ]
        })

        let contacts = try await client.contacts()

        #expect(contacts == [
            Contact(name: "Sam", phoneNumber: "+441", displayNumber: "01 1"),
            Contact(name: "+442", phoneNumber: "+442", displayNumber: "+442"),
        ])
    }

    @Test func aStartedConversationReachesTheInboxAndCanBeSentToStraightAway() async throws {
        let sessions = FakeSessionFactory()
        let client = LibGMMessagingClient(makeSession: sessions.factory)
        let events = client.events()
        try await client.connect(using: Fixtures.session)
        let session = try #require(sessions.latest)
        session.stubCreatedConversation(.with { $0.conversation = ProtoFixtures.conversation("c9", outgoingID: "me-7") })

        let id = try await client.conversation(withPhoneNumber: "+441")
        try await client.sendText("hello", to: id)

        #expect(id == ConversationID("c9"))
        #expect(session.calls.contains("getOrCreate:+441"))
        #expect(try #require(session.sentRequests.first).messagePayload.participantID == "me-7")
        guard case .conversationUpdated(let conversation)? = await events.first(1).first else {
            Issue.record("the inbox wasn't told")
            return
        }
        #expect(conversation.id == id)
    }

    @Test func aResponseWithoutAConversationIsAnError() async throws {
        let sessions = FakeSessionFactory()
        let client = LibGMMessagingClient(makeSession: sessions.factory)
        try await client.connect(using: Fixtures.session)

        await #expect(throws: MessagingError.self) { try await client.conversation(withPhoneNumber: "+441") }
    }

    private func connected(with conversation: GM.Conversation) async throws -> (LibGMMessagingClient, FakeGoogleMessagesSession) {
        let sessions = FakeSessionFactory()
        let client = LibGMMessagingClient(makeSession: sessions.factory)
        let events = client.events()
        try await client.connect(using: Fixtures.session)
        let session = try #require(sessions.latest)
        session.emit(.conversation(conversation))
        _ = await events.first(1)
        return (client, session)
    }

    @Test func aReplyNamesTheMessageItAnswers() async throws {
        let (client, session) = try await connected(with: ProtoFixtures.conversation("c1"))

        try await client.sendText("yes", to: ConversationID("c1"), replyingTo: MessageID("m1"))

        #expect(try #require(session.sentRequests.first).reply.messageID == "m1")
    }

    @Test func anOrdinaryMessageIsNotAReply() async throws {
        let (client, session) = try await connected(with: ProtoFixtures.conversation("c1"))

        try await client.sendText("yes", to: ConversationID("c1"))

        #expect(try #require(session.sentRequests.first).hasReply == false)
    }

    @Test func aStandardReactionIsSentAsItsType() async throws {
        let (client, session) = try await connected(with: ProtoFixtures.conversation("c1"))

        try await client.react(with: "👍", to: MessageID("m1"), in: ConversationID("c1"))

        let request = try #require(session.reactionRequests.first)
        #expect(request.messageID == "m1")
        #expect(request.reactionData.type == .like)
        #expect(request.reactionData.unicode == "👍")
        #expect(request.action == .add)
    }

    @Test func anyOtherEmojiIsSentAsCustom() {
        #expect(ReactionMapper.data(for: "🦊").type == .custom)
    }

    @Test func archivingTellsThePhoneAndEmptiesTheRow() async throws {
        let (client, session) = try await connected(with: ProtoFixtures.conversation("c1"))
        let events = client.events()

        try await client.archive(ConversationID("c1"))

        #expect(try #require(session.updateRequests.first).updateData.status == .archived)
        #expect(await events.first(1) == [.conversationRemoved(ConversationID("c1"))])
    }

    @Test func deletingAConversationUsesTheDeleteAction() async throws {
        let (client, session) = try await connected(with: ProtoFixtures.conversation("c1"))

        try await client.delete(ConversationID("c1"))

        let request = try #require(session.updateRequests.first)
        #expect(request.action == .delete)
        #expect(request.deleteData.conversationID == "c1")
    }

    @Test(arguments: [true, false])
    func mutingSetsTheMuteStatus(isMuted: Bool) async throws {
        let (client, session) = try await connected(with: ProtoFixtures.conversation("c1"))

        try await client.setMuted(isMuted, ConversationID("c1"))

        #expect(try #require(session.updateRequests.first).updateData.mute == (isMuted ? .mute : .unmute))
    }

    @Test func aConversationArchivedOnThePhoneLeavesTheInbox() {
        var archived = ProtoFixtures.conversation("c1")
        archived.status = .archived

        #expect(EventMapper.event(from: .conversation(archived)) == .conversationRemoved(ConversationID("c1")))
        #expect(ConversationMapper.belongsInInbox(ProtoFixtures.conversation("c1")))
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

    private func connectedWithChat(clock: ManualClock = ManualClock()) async throws -> (LibGMMessagingClient, FakeGoogleMessagesSession, ConversationID) {
        let sessions = FakeSessionFactory()
        let client = LibGMMessagingClient(makeSession: sessions.factory, clock: clock)
        try await client.connect(using: Fixtures.session)
        let session = try #require(sessions.latest)
        session.stubCreatedConversation(.with { $0.conversation = ProtoFixtures.conversation("c9", outgoingID: "me-7") })
        return (client, session, try await client.conversation(withPhoneNumber: "+441"))
    }

    @Test func aSendThePhoneNeverAnsweredAlsoReportsThePhoneQuiet() async throws {
        let (client, session, chat) = try await connectedWithChat()
        let events = client.events()
        session.stubSend(.bridge("phone did not respond to request in 1m0s"))

        await #expect(throws: MessagingError.phoneUnreachable) { try await client.sendText("hello", to: chat) }

        #expect(await events.first(1) == [.phoneReachabilityChanged(isReachable: false)])
    }

    @Test func aSendCutOffByRecoveryCountsAsUnanswered() async throws {
        let (client, session, chat) = try await connectedWithChat()
        session.stubSend(.closed)

        await #expect(throws: MessagingError.phoneUnreachable) { try await client.sendText("hello", to: chat) }
    }

    @Test func aTimedOutUploadIsAFailureBecauseNothingWasSent() async throws {
        let (client, session, chat) = try await connectedWithChat()
        session.stubUpload(.bridge("request timeout"))
        let file = OutgoingAttachment(data: Data("x".utf8), fileName: "a.png", mimeType: "image/png")

        await #expect(throws: LibGMMessagingClient.uploadFailed) { try await client.sendAttachment(file, caption: nil, to: chat) }

        #expect(session.sentRequests.isEmpty)
    }

    private func opening(_ chat: ConversationID, on client: LibGMMessagingClient) -> Task<Void, Never> {
        Task { _ = try? await client.messages(in: chat, before: nil, limit: 20) }
    }

    @Test func aChatStillUnansweredAfterFiveSecondsReportsThePhoneSlow() async throws {
        let clock = ManualClock()
        let (client, session, chat) = try await connectedWithChat(clock: clock)
        let events = client.events()
        let release = session.holdFetches()
        let opened = opening(chat, on: client)
        #expect(await eventually { clock.sleeperCount == 1 })

        clock.advance(by: LibGMMessagingClient.answerExpected)

        #expect(await events.first(1) == [.phoneSlowToAnswer])
        release.yield()
        await opened.value
    }

    @Test func theAnswerAfterASilenceSaysThePhoneIsBack() async throws {
        let clock = ManualClock()
        let (client, session, chat) = try await connectedWithChat(clock: clock)
        let events = client.events()
        let release = session.holdFetches()
        let opened = opening(chat, on: client)
        #expect(await eventually { clock.sleeperCount == 1 })
        clock.advance(by: LibGMMessagingClient.answerExpected)
        #expect(await events.first(1) == [.phoneSlowToAnswer])

        release.yield()
        await opened.value

        #expect(await events.first(1) == [.phoneReachabilityChanged(isReachable: true)])
    }

    @Test func aPromptAnswerSaysNothing() async throws {
        let clock = ManualClock()
        let (client, session, chat) = try await connectedWithChat(clock: clock)
        let events = client.events()

        await opening(chat, on: client).value
        session.emit(.loggedOut)

        #expect(await events.first(1) == [.loggedOut])
        #expect(await eventually { clock.sleeperCount == 0 })
    }

    @Test func anyAnswerAfterATimedOutRequestSaysThePhoneIsBack() async throws {
        let (client, session, chat) = try await connectedWithChat()
        let events = client.events()
        session.stubSend(.bridge("phone did not respond to request in 1m0s"))
        await #expect(throws: MessagingError.phoneUnreachable) { try await client.sendText("hello", to: chat) }

        await opening(chat, on: client).value

        #expect(await events.first(2) == [.phoneReachabilityChanged(isReachable: false), .phoneReachabilityChanged(isReachable: true)])
    }

    @Test func aDownloadFromGoogleDoesNotCountAsThePhoneAnswering() async throws {
        let (client, session, chat) = try await connectedWithChat()
        let events = client.events()
        session.stubSend(.bridge("phone did not respond to request in 1m0s"))
        await #expect(throws: MessagingError.phoneUnreachable) { try await client.sendText("hello", to: chat) }

        _ = try await client.attachmentData(Attachment(id: "m1", fileName: "", mimeType: "image/png", byteCount: nil, accessKey: Data("secret".utf8)))
        session.emit(.loggedOut)

        #expect(await events.first(2) == [.phoneReachabilityChanged(isReachable: false), .loggedOut])
    }

    @Test func anInboxLoadThePhoneIgnoresChangesNothingAndCanBeRetried() async throws {
        let (client, session, _) = try await connectedWithChat()
        let events = client.events()
        session.stubInbox(.failure(.bridge("phone did not respond to request in 1m0s")))
        session.emit(.settings(GM.Settings()))
        #expect(await eventually { session.calls.contains("list:inbox:50") })

        session.stubInbox(.success(GM.ListConversationsResponse()))
        #expect(await eventually {
            session.emit(.settings(GM.Settings()))
            return session.calls.filter { $0 == "list:inbox:50" }.count >= 2
        })

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
