import Foundation
import MessagingApplication
import MessagingDomain
import MessagingTestSupport
@testable import Presentation
import Testing

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func at(_ minutes: Double, day: Double = 0) -> Date {
    Date(timeIntervalSince1970: day * 86_400 + 12 * 3_600 + minutes * 60)
}

@Suite struct ThreadReducerTests {
    private func state(after mutations: ThreadMutation...) -> ThreadState {
        mutations.reduce(ThreadState(conversation: Fixtures.conversation("c1")), ThreadReducer.reduce)
    }

    @Test func mergeReplacesByIDAndKeepsSendOrder() {
        let first = Fixtures.message("a", sentAt: at(1), status: .sending)
        let second = Fixtures.message("b", sentAt: at(2))
        let firstDelivered = Fixtures.message("a", sentAt: at(1), status: .delivered)

        let merged = ThreadReducer.merge([firstDelivered], into: [second, first])

        #expect(merged.map(\.id.rawValue) == ["a", "b"])
        #expect(merged.first?.status == .delivered)
    }

    @Test func successfulSendClearsTheDraft() {
        let sending = state(after: .draftChanged("hi"), .sending)
        #expect(sending.isSending && !sending.canSend)

        let sent = ThreadReducer.reduce(sending, .sent("hi"))
        #expect(sent.draft == "" && !sent.isSending)
    }

    @Test func textTypedWhileSendingIsKept() {
        let sent = state(after: .draftChanged("hi"), .sending, .draftChanged("hi there"), .sent("hi"))

        #expect(sent.draft == "hi there" && !sent.isSending)
    }

    @Test func aRenamedConversationUpdatesTheTitle() {
        let state = ThreadReducer.reduce(
            ThreadState(conversation: Fixtures.conversation("c1", title: "Old")),
            .conversationChanged(Fixtures.conversation("c1", title: "New"))
        )

        #expect(state.title == "New")
    }

    @Test func failedSendKeepsTheDraftAndShowsWhy() {
        let failed = state(after: .draftChanged("hi"), .sending, .sendFailed("offline"))

        #expect(failed.draft == "hi")
        #expect(failed.sendError == "offline")
        #expect(failed.canSend)
    }

    @Test(arguments: ["", "   ", "\n"])
    func blankDraftCannotBeSent(draft: String) {
        #expect(ThreadState(conversation: Fixtures.conversation("c1"), draft: draft).canSend == false)
    }

    @Test func olderHistoryOnlyWhileThereIsACursor() {
        let loaded = state(after: .historyLoaded(MessagePage(messages: [], olderCursor: HistoryCursor(token: "t"))))
        #expect(loaded.canLoadOlder)

        let loading = ThreadReducer.reduce(loaded, .olderLoading)
        #expect(loading.canLoadOlder == false)

        let finished = ThreadReducer.reduce(loading, .olderLoaded(MessagePage(messages: [], olderCursor: nil)))
        #expect(finished.canLoadOlder == false)
    }
}

@Suite struct ThreadLayoutTests {
    private let me = Sender.me
    private let sam = Sender.participant(ParticipantID("sam"))

    @Test func groupsQuickRepliesFromOneSenderIntoABurst() {
        let messages = [
            Fixtures.message("1", from: sam, sentAt: at(0)),
            Fixtures.message("2", from: sam, sentAt: at(2)),
            Fixtures.message("3", from: sam, sentAt: at(20)),  // too long after: new burst
            Fixtures.message("4", from: me, sentAt: at(21)),
        ]

        let bubbles = bubbles(messages)

        #expect(bubbles.map(\.endsBurst) == [false, true, true, true])
    }

    @Test func insertsASeparatorForEachNewDay() {
        let messages = [
            Fixtures.message("1", sentAt: at(0, day: 0)),
            Fixtures.message("2", sentAt: at(1, day: 0)),
            Fixtures.message("3", sentAt: at(0, day: 1)),
        ]

        let items = ThreadLayout.items(for: messages, in: Fixtures.conversation("c1"), calendar: utc)

        #expect(items.map(\.isSeparator) == [true, false, false, true, false])
    }

    @Test func namesSendersOnlyInGroupsAndOnlyAtTheStartOfABurst() {
        let group = Conversation(
            id: ConversationID("c1"), title: "Family", preview: nil, lastActivity: at(0),
            isUnread: false, isGroup: true,
            participants: [Participant(id: ParticipantID("sam"), displayName: "Sam", phoneNumber: nil, isMe: false)]
        )
        let messages = [
            Fixtures.message("1", from: sam, sentAt: at(0)),
            Fixtures.message("2", from: sam, sentAt: at(1)),
            Fixtures.message("3", from: me, sentAt: at(2)),
        ]

        let names = bubbles(messages, in: group).map(\.senderName)

        #expect(names == ["Sam", nil, nil])
    }

    @Test func deliveryStatusShowsOnlyOnMyNewestMessage() {
        let messages = [
            Fixtures.message("1", from: me, sentAt: at(0), status: .read),
            Fixtures.message("2", from: me, sentAt: at(1), status: .delivered),
            Fixtures.message("3", from: sam, sentAt: at(2)),
        ]

        #expect(bubbles(messages).map(\.status) == [nil, .delivered, nil])
    }

    private func bubbles(_ messages: [Message], in conversation: Conversation = Fixtures.conversation("c1")) -> [MessageBubble] {
        ThreadLayout.items(for: messages, in: conversation, calendar: utc).compactMap(\.bubble)
    }
}

@MainActor @Suite struct ThreadViewModelTests {
    @Test func loadsHistoryAndMarksTheNewestIncomingMessageRead() async {
        let client = FakeMessagingClient()
        client.stubPage(MessagePage(messages: [Fixtures.message("m1"), Fixtures.message("m2", from: .me)], olderCursor: nil))
        let viewModel = makeViewModel(client)
        let running = Task { await viewModel.run() }

        #expect(await eventually { viewModel.state.history == .loaded })
        #expect(await eventually { client.calls.contains(.markRead(ConversationID("c1"), MessageID("m1"))) })
        running.cancel()
    }

    @Test func liveMessagesAppearAndAreMarkedRead() async {
        let client = FakeMessagingClient()
        let viewModel = makeViewModel(client)
        let running = Task { await viewModel.run() }
        #expect(await eventually { viewModel.state.history == .loaded })

        client.emit(.messageReceived(Fixtures.message("new", sentAt: at(5)), isHistorical: false))

        #expect(await eventually { viewModel.state.messages.map(\.id.rawValue) == ["new"] })
        #expect(await eventually { client.calls.contains(.markRead(ConversationID("c1"), MessageID("new"))) })
        running.cancel()
    }

    @Test func sendingTrimsAndClearsTheDraft() async {
        let client = FakeMessagingClient()
        let viewModel = makeViewModel(client)

        viewModel.send(.draftChanged(" on my way "))
        await viewModel.send(.sendTapped).value

        #expect(client.calls == [.sendText("on my way", ConversationID("c1"))])
        #expect(viewModel.state.draft == "")
    }

    @Test func failedSendExplainsInPlainWords() async {
        let client = FakeMessagingClient()
        client.stubSend(throwing: .phoneUnreachable)
        let viewModel = makeViewModel(client)

        viewModel.send(.draftChanged("hi"))
        await viewModel.send(.sendTapped).value

        #expect(viewModel.state.sendError == "Your phone isn't responding. Check it's on and connected.")
        #expect(viewModel.state.draft == "hi")
    }

    @Test func aThreadBehindAnotherAppWaitsToSendItsReadReceipt() async {
        let client = FakeMessagingClient()
        client.stubPage(MessagePage(messages: [Fixtures.message("m1")], olderCursor: nil))
        let focus = ConversationFocus()
        focus.select(ConversationID("c1"))
        let viewModel = makeViewModel(client, focus: focus)
        let running = Task { await viewModel.run() }
        let receipt = FakeMessagingClient.Call.markRead(ConversationID("c1"), MessageID("m1"))

        #expect(await eventually { viewModel.state.messages.count == 1 })
        #expect(!client.calls.contains(receipt))

        focus.setAppActive(true)

        #expect(await eventually { client.calls.contains(receipt) })
        running.cancel()
    }

    private func visibleFocus() -> ConversationFocus {
        let focus = ConversationFocus()
        focus.select(ConversationID("c1"))
        focus.setAppActive(true)
        return focus
    }

    private func makeViewModel(_ client: FakeMessagingClient, focus: ConversationFocus? = nil) -> ThreadViewModel {
        ThreadViewModel(
            conversation: Fixtures.conversation("c1"),
            loadHistory: LoadThreadHistory(client: client),
            observeThread: ObserveThread(client: client),
            sendText: SendText(client: client),
            markRead: MarkConversationRead(client: client),
            focus: focus ?? visibleFocus(),
            loadAttachment: LoadAttachment(client: client),
            openFile: { _, _ in }
        )
    }
}

private extension ThreadItem {
    var isSeparator: Bool {
        if case .daySeparator = self { return true }
        return false
    }

    var bubble: MessageBubble? {
        if case .bubble(let bubble) = self { return bubble }
        return nil
    }
}
