import Foundation
import MessagingDomain
import Testing
import UserNotifications
@testable import UserNotificationsAdapter

@Suite struct SystemNotificationPresenterTests {
    @Test func aPhotoIsNamedForItsFormat() {
        #expect(SystemNotificationPresenter.fileExtension(of: Data([0x89, 0x50, 0x4E, 0x47, 0x0D])) == "png")
        #expect(SystemNotificationPresenter.fileExtension(of: Data([0xFF, 0xD8, 0xFF])) == "jpg")
    }

    @Test func noPhotoMeansNoAttachment() {
        #expect(SystemNotificationPresenter.content(for: notification).attachments.isEmpty)
    }

    private let notification = MessageNotification(
        messageID: MessageID("m1"),
        conversationID: ConversationID("c1"),
        title: "Sam",
        body: "Pub at 7?"
    )

    @Test func contentCarriesTheWordingAndGroupsByConversation() {
        let content = SystemNotificationPresenter.content(for: notification)

        #expect(content.title == "Sam")
        #expect(content.body == "Pub at 7?")
        #expect(content.threadIdentifier == "c1")
    }

    @Test func aClickFindsItsWayBackToTheConversation() {
        let content = SystemNotificationPresenter.content(for: notification)

        #expect(SystemNotificationPresenter.conversationID(from: content.userInfo) == ConversationID("c1"))
        #expect(SystemNotificationPresenter.conversationID(from: [:]) == nil)
    }
}
