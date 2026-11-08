import Foundation
@testable import LibGMAdapter
import LibGMKit
import MessagingDomain
import Testing

@Suite struct ConversationMapperTests {
    @Test func mapsTheInboxFields() {
        var proto = ProtoFixtures.conversation("c1", name: "Family")
        proto.unread = true
        proto.isGroupChat = true
        proto.latestMessage.displayContent = "dinner?"
        proto.latestMessage.displayName = "Mum"

        let conversation = ConversationMapper.conversation(from: proto)

        #expect(conversation.id == ConversationID("c1"))
        #expect(conversation.title == "Family")
        #expect(conversation.isUnread && conversation.isGroup)
        #expect(conversation.preview == MessagePreview(text: "dinner?", senderName: "Mum", isFromMe: false))
        #expect(conversation.lastActivity == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func participantNameFallsBackToTheNumber() {
        var proto = GM.Participant()
        proto.id.participantID = "p1"
        proto.formattedNumber = "07700 900123"

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
        var info = GM.MessageInfo()
        info.mediaContent.mediaID = "media-1"
        info.mediaContent.mediaName = "photo.jpg"
        info.mediaContent.mimeType = "image/jpeg"
        info.mediaContent.size = 2048

        let part = MessageMapper.part(from: info)

        #expect(part == .attachment(Attachment(id: "media-1", fileName: "photo.jpg", mimeType: "image/jpeg", byteCount: 2048)))
    }
}

@Suite struct CursorCodecTests {
    @Test func roundTrips() throws {
        var cursor = GM.Cursor()
        cursor.lastItemID = "m|9"     // separator inside the ID survives
        cursor.lastItemTimestamp = 42

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
        var conversation = ProtoFixtures.conversation("c1", outgoingID: "me-2")
        conversation.simCard.simdata.simpayload.simnumber = 2

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
        #expect(EventMapper.event(from: .qrCode("qr")) == .pairingCode("qr"))
        #expect(EventMapper.event(from: .phoneReachable(false)) == .phoneReachabilityChanged(isReachable: false))
        #expect(EventMapper.event(from: .fatalError("revoked")) == .connectionLost(reason: "revoked"))
        #expect(EventMapper.event(from: .sessionUpdated(Data([1]))) == .sessionChanged(SessionData(bytes: Data([1]))))
    }

    @Test func dropsSystemNoticeMessages() {
        let notice = ProtoFixtures.message("t", status: .tombstoneParticipantLeft)
        #expect(EventMapper.event(from: .message(notice, isHistorical: false)) == nil)
    }

    @Test(arguments: [
        (LibGMError.bridge("not logged in"), MessagingError.notPaired),
        (.invalidSavedSession, .notPaired),
        (.bridge("request timeout"), .phoneUnreachable),
        (.bridge("something odd"), .backend("something odd")),
    ])
    func mapsErrors(error: LibGMError, expected: MessagingError) {
        #expect(ErrorMapper.error(from: error) == expected)
    }
}
