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
    @Test func mergeReplacesByIDAndKeepsSendOrder() {
        let first = Fixtures.message("a", sentAt: at(1), status: .sending)
        let second = Fixtures.message("b", sentAt: at(2))
        let firstDelivered = Fixtures.message("a", sentAt: at(1), status: .delivered)

        let merged = ThreadReducer.merge([firstDelivered], into: [second, first])

        #expect(merged.map(\.id.rawValue) == ["a", "b"])
        #expect(merged.first?.status == .delivered)
    }

    @Test func successfulSendClearsTheDraft() {
        var state = ThreadState(conversation: Fixtures.conversation("c1"))
        state = ThreadReducer.reduce(state, .draftChanged("hi"))
        state = ThreadReducer.reduce(state, .sending)
        #expect(state.isSending && !state.canSend)

        state = ThreadReducer.reduce(state, .sent)
        #expect(state.draft == "" && !state.isSending)
    }

    @Test func failedSendKeepsTheDraftAndShowsWhy() {
        var state = ThreadState(conversation: Fixtures.conversation("c1"))
        state = ThreadReducer.reduce(state, .draftChanged("hi"))
        state = ThreadReducer.reduce(state, .sending)

        state = ThreadReducer.reduce(state, .sendFailed("offline"))

        #expect(state.draft == "hi")
        #expect(state.sendError == "offline")
        #expect(state.canSend)
    }

    @Test(arguments: ["", "   ", "\n"])
    func blankDraftCannotBeSent(draft: String) {
        var state = ThreadState(conversation: Fixtures.conversation("c1"))
        state.draft = draft
        #expect(state.canSend == false)
    }

    @Test func olderHistoryOnlyWhileThereIsACursor() {
        var state = ThreadState(conversation: Fixtures.conversation("c1"))
        state = ThreadReducer.reduce(state, .historyLoaded(MessagePage(messages: [], olderCursor: HistoryCursor(token: "t"))))
        #expect(state.canLoadOlder)

        state = ThreadReducer.reduce(state, .olderLoading)
        #expect(state.canLoadOlder == false)

        state = ThreadReducer.reduce(state, .olderLoaded(MessagePage(messages: [], olderCursor: nil)))
        #expect(state.canLoadOlder == false)
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

    private func makeViewModel(_ client: FakeMessagingClient) -> ThreadViewModel {
        ThreadViewModel(
            conversation: Fixtures.conversation("c1"),
            loadHistory: LoadThreadHistory(client: client),
            observeThread: ObserveThread(client: client),
            sendText: SendText(client: client),
            markRead: MarkConversationRead(client: client)
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
