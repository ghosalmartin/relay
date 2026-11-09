import Foundation
import MessagingApplication
import MessagingDomain
import MessagingTestSupport
@testable import Presentation
import Testing

private let chat = ConversationID("c1")
private let original = Fixtures.message("m1")

@MainActor
@Suite struct ThreadActionsTests {
    private func make(_ client: FakeMessagingClient, session: LiveSession? = nil) -> ThreadViewModel {
        ThreadViewModel(
            conversation: Fixtures.conversation("c1"),
            loadHistory: LoadThreadHistory(client: client),
            observeThread: ObserveThread(client: client),
            sendText: SendText(client: client),
            markRead: MarkConversationRead(client: client),
            focus: ConversationFocus(),
            loadAttachment: LoadAttachment(client: client),
            openFile: { _, _ in },
            sendAttachment: SendAttachment(client: client),
            observeConnectionStatus: ObserveConnectionStatus(session: session ?? LiveSession(client: client)),
            sendReaction: SendReaction(client: client),
            deleteMessage: DeleteMessage(client: client)
        )
    }

    private func pageCalls(_ client: FakeMessagingClient) -> Int {
        client.calls.filter { if case .messages = $0 { true } else { false } }.count
    }

    @Test func aChatReloadsWhenThePhoneComesBack() async throws {
        let client = FakeMessagingClient()
        let session = LiveSession(client: client)
        session.connection.set(.online)
        let viewModel = make(client, session: session)
        let running = Task { await viewModel.run() }
        defer { running.cancel() }
        try await eventually { pageCalls(client) == 1 }

        session.connection.set(.phoneUnreachable)
        try await eventually { viewModel.state.connection == .phoneUnreachable }
        client.stubPage(MessagePage(messages: [original], olderCursor: nil))
        session.connection.set(.online)

        try await eventually { viewModel.state.messages == [original] }
        #expect(pageCalls(client) == 2)
    }

    @Test func aChatLeftOnlineDoesNotReload() async throws {
        let client = FakeMessagingClient()
        let session = LiveSession(client: client)
        session.connection.set(.online)
        let viewModel = make(client, session: session)
        let running = Task { await viewModel.run() }
        defer { running.cancel() }
        try await eventually { viewModel.state.connection == .online && pageCalls(client) == 1 }

        session.connection.set(.online)
        await Task.yield()

        #expect(pageCalls(client) == 1)
    }

    @Test func aReplyGoesOutAgainstItsMessageAndThenStops() async {
        let client = FakeMessagingClient()
        let viewModel = make(client)
        viewModel.send(.replyTapped(original.id))
        viewModel.send(.draftChanged("yes"))

        await viewModel.send(.sendTapped).value

        #expect(client.calls == [.sendReply("yes", chat, original.id)])
        #expect(viewModel.state.replyTarget == nil)
    }

    @Test func aFileCanBeAReplyToo() async {
        let client = FakeMessagingClient()
        let file = OutgoingAttachment(data: Data("x".utf8), fileName: "a.png", mimeType: "image/png")
        let viewModel = make(client)
        viewModel.send(.replyTapped(original.id))
        viewModel.send(.fileRead(file))

        await viewModel.send(.sendTapped).value

        #expect(client.calls == [.sendFileReply(file, caption: nil, chat, original.id)])
    }

    @Test func aFailedReplyStaysAReply() async {
        let client = FakeMessagingClient()
        client.stubSend(throwing: .notPaired)
        let viewModel = make(client)
        viewModel.send(.replyTapped(original.id))
        viewModel.send(.draftChanged("yes"))

        await viewModel.send(.sendTapped).value

        #expect(viewModel.state.replyTarget == original.id)
    }

    @Test func aReactionIsSentToTheMessage() async {
        let client = FakeMessagingClient()
        let viewModel = make(client)

        await viewModel.send(.reactionChosen("👍", original.id)).value

        #expect(client.calls == [.react("👍", original.id, chat)])
    }

    @Test func aFailedReactionIsExplainedWithoutTouchingASend() async {
        let client = FakeMessagingClient()
        client.stubAction(throwing: .phoneUnreachable)
        let viewModel = make(client)

        await viewModel.send(.reactionChosen("👍", original.id)).value

        #expect(viewModel.state.sendError?.contains("isn't responding") == true)
    }

    @Test func deletingAsksFirst() async {
        let client = FakeMessagingClient()
        let viewModel = make(client)

        viewModel.send(.deleteTapped(original.id))
        #expect(viewModel.state.confirmingDelete == original.id)
        #expect(client.calls.isEmpty)

        viewModel.send(.deleteCancelled)
        #expect(viewModel.state.confirmingDelete == nil)
        #expect(client.calls.isEmpty)
    }

    @Test func aConfirmedDeleteTakesTheMessageOffTheScreen() async {
        let client = FakeMessagingClient()
        client.stubPage(MessagePage(messages: [original], olderCursor: nil))
        let viewModel = make(client)
        await viewModel.send(.retryHistoryTapped).value
        viewModel.send(.deleteTapped(original.id))

        await viewModel.send(.deleteConfirmed).value

        #expect(client.calls.contains(.deleteMessage(original.id)))
        #expect(viewModel.state.messages.isEmpty)
        #expect(viewModel.state.confirmingDelete == nil)
    }

    @Test func aFailedDeleteKeepsTheMessage() async {
        let client = FakeMessagingClient()
        client.stubPage(MessagePage(messages: [original], olderCursor: nil))
        client.stubAction(throwing: .phoneUnreachable)
        let viewModel = make(client)
        await viewModel.send(.retryHistoryTapped).value
        viewModel.send(.deleteTapped(original.id))

        await viewModel.send(.deleteConfirmed).value

        #expect(viewModel.state.messages == [original])
        #expect(viewModel.state.sendError != nil)
    }
}

@Suite struct ThreadActionsStateTests {
    private let base = ThreadState(conversation: Fixtures.conversation("c1"), messages: [original], olderCursor: HistoryCursor(token: "older"))

    @Test func catchingUpKeepsThePlaceInOlderHistory() {
        let next = ThreadReducer.reduce(base, .caughtUp(MessagePage(messages: [Fixtures.message("m2")], olderCursor: HistoryCursor(token: "newest"))))

        #expect(next.olderCursor == HistoryCursor(token: "older"))
        #expect(next.messages.count == 2)
        #expect(next.history == .loaded)
    }

    @Test func aDeletedMessageStopsBeingRepliedTo() {
        let replying = ThreadReducer.reduce(base, .replyStarted(original.id))

        #expect(ThreadReducer.reduce(replying, .messageRemoved(original.id)).replyTarget == nil)
    }

    @Test func theReplyPreviewQuotesTheMessage() {
        let text = Fixtures.message("m3", text: "See you there")
        let state = ThreadState(conversation: Fixtures.conversation("c1"), messages: [text], replyTarget: text.id)

        #expect(state.replyPreview == "See you there")
    }

    @Test func messagesWithNothingToShowOfferNoActions() {
        let deleted = Fixtures.message("m4", status: .deleted)
        let items = ThreadLayout.items(for: [deleted], in: Fixtures.conversation("c1"), calendar: .current)

        guard case .bubble(let bubble)? = items.last else {
            Issue.record("no bubble")
            return
        }
        #expect(!bubble.canTakeActions)
    }
}
