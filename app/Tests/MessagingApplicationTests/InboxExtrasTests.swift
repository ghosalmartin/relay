import Foundation
@testable import MessagingApplication
import MessagingDomain
import MessagingTestSupport
import Synchronization
import Testing

private final class RecordingBadge: UnreadBadge {
    private let labels = Mutex<[String?]>([])
    var shown: [String?] { labels.withLock { $0 } }
    func show(_ label: String?) async { labels.withLock { $0.append(label) } }
}

@Suite struct ShowUnreadCountTests {
    @Test func countsUnreadConversations() {
        let inbox = [
            Fixtures.conversation("a", isUnread: true),
            Fixtures.conversation("b", isUnread: false),
            Fixtures.conversation("c", isUnread: true),
        ]

        #expect(ShowUnreadCount.label(for: inbox) == "2")
    }

    @Test func nothingUnreadClearsTheBadge() {
        #expect(ShowUnreadCount.label(for: [Fixtures.conversation("a", isUnread: false)]) == nil)
    }

    @Test func theBadgeFollowsTheInbox() async {
        let client = FakeMessagingClient()
        let session = LiveSession(client: client)
        let badge = RecordingBadge()
        let pump = Task { await session.run() }
        let showing = Task { await ShowUnreadCount(observeInbox: ObserveInbox(session: session), badge: badge)() }
        defer {
            pump.cancel()
            showing.cancel()
        }
        #expect(await eventually { badge.shown.last == .some(nil) })

        client.emit(.conversationUpdated(Fixtures.conversation("a", isUnread: true)))

        #expect(await eventually { badge.shown.last == "1" })
    }
}

@Suite struct ReplyFromNotificationTests {
    private let chat = ConversationID("c1")

    @Test func theReplyIsSentToTheConversation() async {
        let client = FakeMessagingClient()
        let presenter = FakeNotificationPresenter()

        await ReplyFromNotification(sendText: SendText(client: client), presenter: presenter)("On my way", to: chat)

        #expect(client.calls == [.sendText("On my way", chat)])
        #expect(presenter.presented.isEmpty)
    }

    @Test func aFailedReplyRaisesAnAlertQuotingIt() async {
        let client = FakeMessagingClient()
        client.stubSend(throwing: .phoneUnreachable)
        let presenter = FakeNotificationPresenter()

        await ReplyFromNotification(sendText: SendText(client: client), presenter: presenter)("On my way", to: chat)

        #expect(presenter.presented.first?.title == "Message not sent")
        #expect(presenter.presented.first?.body.contains("On my way") == true)
        #expect(presenter.presented.first?.conversationID == chat)
    }
}

@Suite struct PairingRetryTests {
    @Test func aPhoneThatMissesPairingIsAskedTwiceMore() async {
        let client = FakeMessagingClient()
        client.stubPairing(throwing: .phoneMissedPairing)

        await #expect(throws: MessagingError.phoneMissedPairing) {
            for try await _ in PairDevice(client: client)(with: Fixtures.accountCookies) {}
        }

        #expect(client.calls.count == 3)
    }

    @Test func aPhoneThatWakesUpFinishesPairing() async throws {
        let client = FakeMessagingClient()
        client.stubPairing(failing: .phoneMissedPairing, times: 1)
        client.onStartPairing = { [weak client] in
            if client?.calls.count == 2 { client?.emit(.paired) }
        }
        let steps = PairDevice(client: client)(with: Fixtures.accountCookies)

        var reached: [PairingStep] = []
        for try await step in steps { reached.append(step) }

        #expect(reached == [.paired])
    }

    @Test func otherFailuresAreNotRetried() async {
        let client = FakeMessagingClient()
        client.stubPairing(throwing: .backend("wrong emoji"))

        await #expect(throws: MessagingError.self) {
            for try await _ in PairDevice(client: client)(with: Fixtures.accountCookies) {}
        }

        #expect(client.calls.count == 1)
    }
}
