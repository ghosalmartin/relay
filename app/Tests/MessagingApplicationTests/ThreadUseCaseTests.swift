@testable import MessagingApplication
import MessagingDomain
import MessagingTestSupport
import Testing

@Suite struct SendTextTests {
    @Test func trimsWhitespaceBeforeSending() async throws {
        let client = FakeMessagingClient()

        try await SendText(client: client)("  hello \n", to: ConversationID("c1"))

        #expect(client.calls == [.sendText("hello", ConversationID("c1"))])
    }

    @Test(arguments: ["", "   ", "\n\t"])
    func rejectsBlankMessagesWithoutTouchingTheNetwork(draft: String) async {
        let client = FakeMessagingClient()

        await #expect(throws: SendText.Failure.emptyMessage) {
            try await SendText(client: client)(draft, to: ConversationID("c1"))
        }
        #expect(client.calls.isEmpty)
    }

    @Test func wrapsClientFailures() async {
        let client = FakeMessagingClient()
        client.stubSend(throwing: .phoneUnreachable)

        await #expect(throws: SendText.Failure.messaging(.phoneUnreachable)) {
            try await SendText(client: client)("hi", to: ConversationID("c1"))
        }
    }
}

@Suite struct LoadThreadHistoryTests {
    @Test func requestsAPageBeforeTheCursor() async throws {
        let client = FakeMessagingClient()
        let cursor = HistoryCursor(token: "t")

        _ = try await LoadThreadHistory(client: client)(ConversationID("c1"), before: cursor)

        #expect(client.calls == [.messages(ConversationID("c1"), cursor, limit: LoadThreadHistory.pageSize)])
    }
}

@Suite struct ObserveThreadTests {
    @Test func passesOnlyMessagesForThatConversation() {
        let mine = Fixtures.message("m1", in: "c1")
        let other = Fixtures.message("m2", in: "c2")

        #expect(ObserveThread.message(in: ConversationID("c1"), from: .messageReceived(mine, isHistorical: false)) == mine)
        #expect(ObserveThread.message(in: ConversationID("c1"), from: .messageReceived(other, isHistorical: false)) == nil)
        #expect(ObserveThread.message(in: ConversationID("c1"), from: .paired) == nil)
    }
}

@Suite struct ConnectionStatusTests {
    @Test func followsTheConnectionLifecycle() async {
        let client = FakeMessagingClient()
        let session = LiveSession(client: client)
        let pump = Task { await session.run() }
        let statuses = ObserveConnectionStatus(session: session)()
        let collected = Task { await statuses.first(4) }

        client.emit(.initialSyncCompleted)
        client.emit(.initialSyncCompleted)              // repeat: dropped
        client.emit(.phoneReachabilityChanged(isReachable: false))
        client.emit(.connectionLost(reason: "revoked"))

        #expect(await collected.value == [.connecting, .online, .phoneUnreachable, .lost(reason: "revoked")])
        pump.cancel()
    }
}
