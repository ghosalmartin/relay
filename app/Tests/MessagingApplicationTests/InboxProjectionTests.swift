import Foundation
@testable import MessagingApplication
import MessagingDomain
import MessagingTestSupport
import Testing

@Suite struct InboxProjectionTests {
    private func inbox(after events: MessagingEvent...) -> InboxProjection {
        events.reduce(InboxProjection()) { $0.applying($1) }
    }

    @Test func ordersConversationsByLatestActivity() {
        let inbox = inbox(after:
            .conversationUpdated(Fixtures.conversation("old", lastActivity: .init(timeIntervalSince1970: 1))),
            .conversationUpdated(Fixtures.conversation("new", lastActivity: .init(timeIntervalSince1970: 2)))
        )

        #expect(inbox.conversations.map(\.id.rawValue) == ["new", "old"])
    }

    @Test func updateReplacesTheExistingConversation() {
        let inbox = inbox(after:
            .conversationUpdated(Fixtures.conversation("c1", preview: "first")),
            .conversationUpdated(Fixtures.conversation("c1", preview: "second"))
        )

        #expect(inbox.conversations.count == 1)
        #expect(inbox.conversations.first?.preview?.text == "second")
    }

    @Test func identicalUpdateChangesNothing() {
        let conversation = Fixtures.conversation("c1")
        let before = inbox(after: .conversationUpdated(conversation))

        #expect(before.applying(.conversationUpdated(conversation)) == before)
    }

    @Test func initialSyncChangesTheInboxOnce() {
        let synced = InboxProjection().applying(.initialSyncCompleted)

        #expect(synced != InboxProjection())
        #expect(synced.applying(.initialSyncCompleted) == synced)
        #expect(synced.hasCompletedInitialSync)
    }

    @Test func logoutEmptiesTheInbox() {
        let inbox = inbox(after: .conversationUpdated(Fixtures.conversation("c1")), .initialSyncCompleted)

        #expect(inbox.applying(.loggedOut) == InboxProjection())
    }

    @Test func pairingAgainEmptiesTheInbox() {
        let inbox = inbox(after: .conversationUpdated(Fixtures.conversation("c1")), .initialSyncCompleted)

        #expect(inbox.applying(.paired) == InboxProjection())
    }

    @Test func unrelatedEventsAreIgnored() {
        let inbox = InboxProjection()

        #expect(inbox.applying(.phoneReachabilityChanged(isReachable: false)) == inbox)
    }
}
