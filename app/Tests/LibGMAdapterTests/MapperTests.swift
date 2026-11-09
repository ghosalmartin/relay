import Foundation
@testable import LibGMAdapter
import LibGMKit
import MessagingDomain
import Testing

@Test func aPhoneThatMissesPairingCanBeRetried() {
    #expect(ErrorMapper.error(from: .bridge("google account pairing: client init timed out")) == .phoneMissedPairing)
}

@Suite struct ConversationMapperTests {
    @Test func mapsTheInboxFields() {
        let proto = GM.Conversation.with {
            $0 = ProtoFixtures.conversation("c1", name: "Family")
            $0.unread = true
            $0.isGroupChat = true
            $0.latestMessage.displayContent = "dinner?"
            $0.latestMessage.displayName = "Mum"
        }

        let conversation = ConversationMapper.conversation(from: proto)

        #expect(conversation.id == ConversationID("c1"))
        #expect(conversation.title == "Family")
        #expect(conversation.isUnread && conversation.isGroup)
        #expect(conversation.preview == MessagePreview(text: "dinner?", senderName: "Mum", isFromMe: false))
        #expect(conversation.lastActivity == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func participantNameFallsBackToTheNumber() {
        let proto = GM.Participant.with {
            $0.id.participantID = "p1"
            $0.formattedNumber = "07700 900123"
        }

        let participant = ConversationMapper.participant(from: proto)

        #expect(participant.displayName == "07700 900123")
        #expect(participant.phoneNumber == "07700 900123")
    }
}

@Suite struct MessageMapperTests {
    @Test func outgoingStatusesMeanTheMessageIsMine() {
        let mine = MessageMapper.message(from: ProtoFixtures.message("m1", status: .outgoingDelivered))
        let theirs = MessageMapper.message(from: ProtoFixtures.message("m2", status: .incomingComplete))

        #expect(mine?.sender == .me)
        #expect(mine?.status == .delivered)
        #expect(theirs?.sender == .participant(ParticipantID("p1")))
        #expect(theirs?.status == .received)
    }

    @Test(arguments: [
        (GM.MessageStatusType.outgoingSending, DeliveryStatus.sending),
        (.outgoingYetToSend, .sending),
        (.outgoingComplete, .sent),
        (.outgoingDisplayed, .read),
        (.outgoingFailedGeneric, .failed),
        (.outgoingCanceled, .failed),
        (.messageDeleted, .deleted),
        (.incomingDeleted, .deleted),
    ])
    func deliveryStatus(status: GM.MessageStatusType, expected: DeliveryStatus) {
        #expect(MessageMapper.deliveryStatus(status) == expected)
    }

    @Test func systemNoticesAreNotMessages() {
        #expect(MessageMapper.message(from: ProtoFixtures.message("t", status: .tombstoneParticipantJoined)) == nil)
    }

    @Test func mediaBecomesAnAttachment() {
        let info = GM.MessageInfo.with {
            $0.mediaContent.mediaID = "media-1"
            $0.mediaContent.mediaName = "photo.jpg"
            $0.mediaContent.mimeType = "image/jpeg"
            $0.mediaContent.size = 2048
        }

        let part = MessageMapper.part(from: info)

        #expect(part == .attachment(Attachment(id: "media-1", fileName: "photo.jpg", mimeType: "image/jpeg", byteCount: 2048)))
    }

    @Test func mediaKeepsTheKeyNeededToDownloadIt() {
        let info = GM.MessageInfo.with {
            $0.mediaContent.mediaID = "media-1"
            $0.mediaContent.decryptionKey = Data("secret".utf8)
        }

        guard case .attachment(let attachment) = MessageMapper.part(from: info) else {
            Issue.record("expected an attachment")
            return
        }
        #expect(attachment.accessKey == Data("secret".utf8))
    }

    @Test func withoutAFullFileTheThumbnailIsUsed() {
        let info = GM.MessageInfo.with {
            $0.mediaContent.thumbnailMediaID = "thumb"
            $0.mediaContent.thumbnailDecryptionKey = Data("thumb-key".utf8)
            $0.mediaContent.mimeType = "image/jpeg"
        }

        #expect(MessageMapper.part(from: info) == .attachment(Attachment(
            id: "thumb", fileName: "", mimeType: "image/jpeg", byteCount: nil, accessKey: Data("thumb-key".utf8)
        )))
    }

    @Test func thePictureEmbeddedInTheMessageIsTheLastResort() {
        let info = GM.MessageInfo.with {
            $0.mediaContent.mediaData = Data("embedded".utf8)
            $0.mediaContent.mimeType = "image/jpeg"
        }

        guard case .attachment(let attachment) = MessageMapper.part(from: info) else {
            Issue.record("expected an attachment")
            return
        }
        #expect(attachment.inlineData == Data("embedded".utf8))
        #expect(!attachment.id.isEmpty)     // state is keyed by ID, so an empty one would collide
    }

    @Test func aFullFileBeatsItsThumbnailAndEmbeddedCopy() {
        let info = GM.MessageInfo.with {
            $0.mediaContent.mediaID = "full"
            $0.mediaContent.decryptionKey = Data("key".utf8)
            $0.mediaContent.thumbnailMediaID = "thumb"
            $0.mediaContent.mediaData = Data("embedded".utf8)
        }

        guard case .attachment(let attachment) = MessageMapper.part(from: info) else {
            Issue.record("expected an attachment")
            return
        }
        #expect(attachment.id == "full")
        #expect(attachment.accessKey == Data("key".utf8))
        #expect(attachment.inlineData == nil)
    }

    @Test func aLocationWithADescriptionBecomesText() {
        let info = GM.MessageInfo.with { $0.locationContent.messageContent.content = "Pub https://maps.example" }

        #expect(MessageMapper.part(from: info) == .text("Pub https://maps.example"))
    }

    @Test func aLocationWithOnlyAMapBecomesAnAttachment() {
        let info = GM.MessageInfo.with {
            $0.locationContent.mediaContent.mediaID = "map"
            $0.locationContent.mediaContent.mimeType = "image/png"
        }

        #expect(MessageMapper.part(from: info) == .attachment(Attachment(id: "map", fileName: "", mimeType: "image/png", byteCount: nil)))
    }

    @Test func anEmptyLocationHasNoPart() {
        let info = GM.MessageInfo.with { $0.locationContent = GM.LocationContent() }

        #expect(MessageMapper.part(from: info) == nil)
    }

    @Test func aStandardReactionIsCountedUnderItsEmoji() {
        let entry = GM.ReactionEntry.with {
            $0.data.type = .like
            $0.participantIds = ["p1", "p2"]
        }

        #expect(ReactionMapper.reaction(from: entry) == Reaction(emoji: "👍", count: 2))
    }

    @Test func aCustomReactionUsesTheEmojiItCarries() {
        let entry = GM.ReactionEntry.with {
            $0.data.type = .custom
            $0.data.unicode = "🦊"
            $0.participantIds = ["p1"]
        }

        #expect(ReactionMapper.reaction(from: entry) == Reaction(emoji: "🦊", count: 1))
    }

    @Test func aReactionNobodyHoldsIsDropped() {
        let entry = GM.ReactionEntry.with { $0.data.type = .like }

        #expect(ReactionMapper.reaction(from: entry) == nil)
    }

    @Test func aReplyPointsAtTheOriginalMessage() throws {
        let proto = ProtoFixtures.message("m2", status: .incomingComplete)
        let reply = GM.Message.with {
            $0 = proto
            $0.replyMessage.messageID = "m1"
        }

        #expect(try #require(MessageMapper.message(from: reply)).replyTo == MessageID("m1"))
        #expect(try #require(MessageMapper.message(from: proto)).replyTo == nil)
    }
}

@Suite struct CursorCodecTests {
    @Test func roundTrips() throws {
        let cursor = GM.Cursor.with {
            $0.lastItemID = "m|9"     // separator inside the ID survives
            $0.lastItemTimestamp = 42
        }

        let token = try #require(CursorCodec.token(from: cursor))
        let decoded = try #require(CursorCodec.cursor(from: token))

        #expect(decoded == cursor)
    }

    @Test func emptyCursorMeansNoMoreHistory() {
        #expect(CursorCodec.token(from: GM.Cursor()) == nil)
        #expect(CursorCodec.cursor(from: HistoryCursor(token: "garbage")) == nil)
    }
}

@Suite struct SendRequestBuilderTests {
    @Test func sendsFromTheConversationsNumberAndSIM() {
        let conversation = GM.Conversation.with {
            $0 = ProtoFixtures.conversation("c1", outgoingID: "me-2")
            $0.simCard.simdata.simpayload.simnumber = 2
        }

        let request = SendRequestBuilder.textMessage("hello", in: conversation, transactionID: "tx")

        #expect(request.conversationID == "c1")
        #expect(request.tmpID == "tx")
        #expect(request.messagePayload.participantID == "me-2")
        #expect(request.messagePayload.messageInfo.first?.messageContent.content == "hello")
        #expect(request.simpayload.simnumber == 2)
    }
}

@Suite struct EventAndErrorMapperTests {
    @Test func mapsLifecycleEvents() {
        #expect(EventMapper.event(from: .qrCode("qr")) == nil)
        #expect(EventMapper.event(from: .googleAccountEmoji("🦊")) == .pairingConfirmationEmoji("🦊"))
        #expect(EventMapper.event(from: .phoneReachable(false)) == .phoneReachabilityChanged(isReachable: false))
        #expect(EventMapper.event(from: .fatalError("revoked")) == .connectionLost(reason: "revoked"))
        #expect(EventMapper.event(from: .sessionUpdated(Data([1]))) == .sessionChanged(SessionData(bytes: Data([1]))))
    }

    @Test(arguments: [
        ("google account pairing: client init timed out (phone hasn't been seen recently)", "hasn't connected"),
        ("google account pairing: no devices found for gaia pairing", "No phone found"),
        ("google account pairing: user chose incorrect emoji on phone", "wrong emoji"),
        ("google account pairing: user cancelled pairing on phone", "cancelled"),
        ("google account pairing: pairing timed out (code: 1/2)", "in time"),
    ])
    func pairingFailuresAreInPlainWords(reason: String, expected: String) {
        guard case .backend(let message) = ErrorMapper.error(from: .bridge(reason)) else {
            Issue.record("expected a backend message")
            return
        }
        #expect(message.contains(expected))
    }

    @Test func dropsSystemNoticeMessages() {
        let notice = ProtoFixtures.message("t", status: .tombstoneParticipantLeft)
        #expect(EventMapper.event(from: .message(notice, isHistorical: false)) == nil)
    }

    @Test(arguments: [
        (LibGMError.bridge("not logged in"), MessagingError.notPaired),
        (.invalidSavedSession, .notPaired),
        (.bridge("request timeout"), .phoneUnreachable),
        (.bridge("phone did not respond to request in 1m0s"), .phoneUnreachable),
        (.bridge("something odd"), .backend("something odd")),
    ])
    func mapsErrors(error: LibGMError, expected: MessagingError) {
        #expect(ErrorMapper.error(from: error) == expected)
    }
}
