import Foundation
@testable import MessagingApplication
import MessagingDomain
import MessagingTestSupport
import Testing

@Suite struct InboxProjectionTests {
    @Test func ordersConversationsByLatestActivity() {
        var inbox = InboxProjection()
        _ = inbox.apply(.conversationUpdated(Fixtures.conversation("old", lastActivity: .init(timeIntervalSince1970: 1))))
        _ = inbox.apply(.conversationUpdated(Fixtures.conversation("new", lastActivity: .init(timeIntervalSince1970: 2))))

        #expect(inbox.conversations.map(\.id.rawValue) == ["new", "old"])
    }

    @Test func updateReplacesTheExistingConversation() {
        var inbox = InboxProjection()
        _ = inbox.apply(.conversationUpdated(Fixtures.conversation("c1", preview: "first")))
        _ = inbox.apply(.conversationUpdated(Fixtures.conversation("c1", preview: "second")))

        #expect(inbox.conversations.count == 1)
        #expect(inbox.conversations.first?.preview?.text == "second")
    }

    @Test func identicalUpdateReportsNoChange() {
        var inbox = InboxProjection()
        let conversation = Fixtures.conversation("c1")
        _ = inbox.apply(.conversationUpdated(conversation))

        let changed = inbox.apply(.conversationUpdated(conversation))

        #expect(changed == false)
    }

    @Test func initialSyncIsReportedOnce() {
        var inbox = InboxProjection()

        let first = inbox.apply(.initialSyncCompleted)
        let second = inbox.apply(.initialSyncCompleted)

        #expect(first)
        #expect(second == false)
        #expect(inbox.hasCompletedInitialSync)
    }

    @Test func logoutEmptiesTheInbox() {
        var inbox = InboxProjection()
        _ = inbox.apply(.conversationUpdated(Fixtures.conversation("c1")))
        _ = inbox.apply(.initialSyncCompleted)

        let changed = inbox.apply(.loggedOut)

        #expect(changed)
        #expect(inbox == InboxProjection())
    }

    @Test func unrelatedEventsAreIgnored() {
        var inbox = InboxProjection()

        let changed = inbox.apply(.phoneReachabilityChanged(isReachable: false))

        #expect(changed == false)
    }
}
