import Foundation
@testable import MessagingApplication
import MessagingDomain
import MessagingTestSupport
import Testing

@Suite struct NotificationDeciderTests {
    private let incoming = Fixtures.message("m1", in: "c1", text: "Pub at 7?")

    private func synced(with conversations: Conversation...) -> NotificationDecider {
        (conversations.map(MessagingEvent.conversationUpdated) + [.initialSyncCompleted])
            .reduce(NotificationDecider()) { $0.deciding($1, visible: nil).next }
    }

    @Test func aNewMessageIsAnnouncedUnderItsConversationTitle() {
        let decider = synced(with: Fixtures.conversation("c1", title: "Sam"))

        let notification = decider.deciding(.messageReceived(incoming, isHistorical: false), visible: nil).notification

        #expect(notification == MessageNotification(
            messageID: MessageID("m1"), conversationID: ConversationID("c1"), title: "Sam", body: "Pub at 7?"
        ))
    }

    @Test func aMessageInAConversationNotSyncedYetStillGetsATitle() {
        let decider = synced()

        let notification = decider.deciding(.messageReceived(incoming, isHistorical: false), visible: nil).notification

        #expect(notification?.title == "New Message")
    }

    @Test func aGroupMessageSaysWhoSentIt() {
        let sam = Participant(id: ParticipantID("p1"), displayName: "Sam", phoneNumber: nil, isMe: false)
        let group = Conversation(id: ConversationID("c1"), title: "Friends", preview: nil, lastActivity: Date(timeIntervalSince1970: 0),
                                 isUnread: true, isGroup: true, participants: [sam])
        let decider = synced(with: group)

        let notification = decider.deciding(.messageReceived(incoming, isHistorical: false), visible: nil).notification

        #expect(notification?.title == "Friends")
        #expect(notification?.body == "Sam: Pub at 7?")
    }

    @Test func aPictureWithNoTextIsDescribed() {
        let photo = Attachment(id: "a1", fileName: "cat.jpg", mimeType: "image/jpeg", byteCount: nil)
        let message = Message(id: MessageID("m1"), conversationID: ConversationID("c1"), sender: .participant(ParticipantID("p1")),
                              sentAt: Date(timeIntervalSince1970: 0), parts: [.attachment(photo)], status: .received)
        let decider = synced()

        #expect(decider.deciding(.messageReceived(message, isHistorical: false), visible: nil).notification?.body == "Photo")
    }

    @Test func historyIsNotNews() {
        let decider = synced()

        #expect(decider.deciding(.messageReceived(incoming, isHistorical: true), visible: nil).notification == nil)
    }

    @Test func myOwnMessagesAreNotAnnounced() {
        let decider = synced()
        let mine = Fixtures.message("m1", from: .me, status: .sent)

        #expect(decider.deciding(.messageReceived(mine, isHistorical: false), visible: nil).notification == nil)
    }

    @Test func deletedMessagesAreNotAnnounced() {
        let decider = synced()
        let deleted = Fixtures.message("m1", status: .deleted)

        #expect(decider.deciding(.messageReceived(deleted, isHistorical: false), visible: nil).notification == nil)
    }

    @Test func nothingIsAnnouncedBeforeTheFirstSyncFinishes() {
        let decider = NotificationDecider()

        #expect(decider.deciding(.messageReceived(incoming, isHistorical: false), visible: nil).notification == nil)
    }

    @Test func aMessageIsAnnouncedOnlyOnce() {
        let first = synced().deciding(.messageReceived(incoming, isHistorical: false), visible: nil)

        #expect(first.notification != nil)
        #expect(first.next.deciding(.messageReceived(incoming, isHistorical: false), visible: nil).notification == nil)
    }

    @Test func aMessageSeenAsHistoryIsNotAnnouncedWhenItIsRepeatedAsLive() {
        let decider = synced().deciding(.messageReceived(incoming, isHistorical: true), visible: nil).next

        #expect(decider.deciding(.messageReceived(incoming, isHistorical: false), visible: nil).notification == nil)
    }

    @Test func theConversationOnScreenIsNotAnnounced() {
        let decider = synced()

        #expect(decider.deciding(.messageReceived(incoming, isHistorical: false), visible: ConversationID("c1")).notification == nil)
    }

    @Test func anotherConversationIsAnnouncedWhileOneIsOnScreen() {
        let decider = synced()

        #expect(decider.deciding(.messageReceived(incoming, isHistorical: false), visible: ConversationID("other")).notification != nil)
    }
}

@Suite struct AttentionTests {
    @Test func aConversationOnlyCountsAsVisibleWhileTheAppIsFrontmost() {
        let focus = ConversationFocus()
        let id = ConversationID("c1")

        focus.select(id)
        #expect(!focus.isVisible(id))

        focus.setAppActive(true)
        #expect(focus.isVisible(id))

        focus.setAppActive(false)
        #expect(!focus.isVisible(id))
    }
}

@Suite struct NotifyIncomingMessagesTests {
    @Test func asksPermissionOnceThenPresentsNewMessages() async {
        let client = FakeMessagingClient()
        let presenter = FakeNotificationPresenter()
        let notify = NotifyIncomingMessages(client: client, presenter: presenter, focus: ConversationFocus())

        client.emit(.initialSyncCompleted)                     // before it runs: the subscription is already live
        client.emit(.initialSyncCompleted)
        client.emit(.messageReceived(Fixtures.message("m1"), isHistorical: false))
        let task = Task { await notify() }

        #expect(await eventually { presenter.presented.count == 1 })
        #expect(presenter.authorizationRequests == 1)
        task.cancel()
    }

    @Test func anAlertCarriesTheSendersPhotoOnceLoaded() async {
        let client = FakeMessagingClient()
        let presenter = FakeNotificationPresenter()
        let book = AvatarBook()
        book.add([ParticipantID("p1"): Data("photo".utf8)])
        let notify = NotifyIncomingMessages(client: client, presenter: presenter, focus: ConversationFocus(), avatars: book)

        client.emit(.initialSyncCompleted)
        client.emit(.messageReceived(Fixtures.message("m1"), isHistorical: false))
        let task = Task { await notify() }

        #expect(await eventually { presenter.presented.first?.senderPhoto == Data("photo".utf8) })
        task.cancel()
    }

    @Test func anAlertForSomeoneWithoutALoadedPhotoStillAppears() async {
        let client = FakeMessagingClient()
        let presenter = FakeNotificationPresenter()
        let notify = NotifyIncomingMessages(client: client, presenter: presenter, focus: ConversationFocus(), avatars: AvatarBook())

        client.emit(.initialSyncCompleted)
        client.emit(.messageReceived(Fixtures.message("m1"), isHistorical: false))
        let task = Task { await notify() }

        #expect(await eventually { presenter.presented.count == 1 })
        #expect(presenter.presented.first?.senderPhoto == nil)
        task.cancel()
    }

    @Test func loadedPhotosGoInTheBook() async throws {
        let client = FakeMessagingClient()
        let book = AvatarBook()
        client.stubAvatars(.success([ParticipantID("p1"): Data("photo".utf8)]))

        _ = try await LoadAvatars(client: client, book: book)([ParticipantID("p1")])

        #expect(book.photo(of: ParticipantID("p1")) == Data("photo".utf8))
    }

    @Test func clearsAlertsOnceTheConversationIsOnScreen() async {
        let client = FakeMessagingClient()
        let presenter = FakeNotificationPresenter()
        let focus = ConversationFocus()
        let task = Task { await NotifyIncomingMessages(client: client, presenter: presenter, focus: focus)() }

        focus.select(ConversationID("c1"))
        focus.setAppActive(true)

        #expect(await eventually { presenter.dismissed == [ConversationID("c1")] })
        task.cancel()
    }
}
