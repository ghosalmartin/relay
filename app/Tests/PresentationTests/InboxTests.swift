import Foundation
import MessagingApplication
import MessagingDomain
import MessagingTestSupport
@testable import Presentation
import Testing

@Suite struct InboxStateTests {
    @Test func searchMatchesTitleOrPreviewIgnoringCase() {
        let state = InboxState(conversations: [
            Fixtures.conversation("1", title: "Mum", preview: "dinner at 7?"),
            Fixtures.conversation("2", title: "Dentist", preview: "Reminder"),
        ])

        #expect(state.with(searchText: "DINNER").rows.map(\.id.rawValue) == ["1"])
        #expect(state.with(searchText: "dent").rows.map(\.id.rawValue) == ["2"])
        #expect(state.with(searchText: "  ").rows.count == 2)
    }

    @Test func emptyOnlyOnceSyncHasFinished() {
        #expect(InboxState().isEmpty == false)
        #expect(InboxState(isSyncing: false).isEmpty)
    }

    @Test(arguments: [
        (ConnectionStatus.connecting, ConnectionBanner?.some(.connecting)),
        (.phoneUnreachable, .phoneUnreachable),
        (.reconnecting, .reconnecting),
        (.online, nil),
    ])
    func bannerFollowsConnection(status: ConnectionStatus, banner: ConnectionBanner?) {
        #expect(InboxState(connection: status).banner == banner)
    }
}

@Suite struct ConversationRowTests {
    @Test(arguments: [
        ("Alex Smith", "AS"),
        ("mum", "M"),
        ("Jean Paul Gaultier", "JP"),
        ("+44 7700 900123", "#"),
        ("", "#"),
    ])
    func initials(title: String, expected: String) {
        #expect(ConversationRow.initials(of: title) == expected)
    }

    @Test func previewSaysWhoSentIt() {
        #expect(ConversationRow.previewText(MessagePreview(text: "hi", senderName: nil, isFromMe: true)) == "You: hi")
        #expect(ConversationRow.previewText(MessagePreview(text: "hi", senderName: "Sam", isFromMe: false)) == "Sam: hi")
        #expect(ConversationRow.previewText(MessagePreview(text: "hi", senderName: nil, isFromMe: false)) == "hi")
        #expect(ConversationRow.previewText(nil) == "")
    }
}

@Suite struct InboxReducerTests {
    @Test func selectionSurvivesUpdatesWhileItsConversationExists() {
        let loaded = InboxReducer.reduce(InboxState(), .inboxChanged(snapshot("a", "b")))
        let selected = InboxReducer.reduce(loaded, .selected(ConversationID("a")))

        let stillThere = InboxReducer.reduce(selected, .inboxChanged(snapshot("a")))
        #expect(stillThere.selection == ConversationID("a"))

        let gone = InboxReducer.reduce(stillThere, .inboxChanged(snapshot("b")))
        #expect(gone.selection == nil)
    }

    @Test func openingASyncedConversationSelectsIt() {
        let state = InboxReducer.reduce(InboxReducer.reduce(InboxState(), .inboxChanged(snapshot("a"))), .openRequested(ConversationID("a")))

        #expect(state.selection == ConversationID("a"))
        #expect(state.pendingOpen == nil)
    }

    @Test func openingAConversationThatHasNotSyncedWaitsForIt() {
        let waiting = InboxReducer.reduce(InboxState(), .openRequested(ConversationID("a")))
        #expect(waiting.selection == nil)

        let stillWaiting = InboxReducer.reduce(waiting, .inboxChanged(snapshot("b")))
        #expect(stillWaiting.selection == nil)

        let arrived = InboxReducer.reduce(stillWaiting, .inboxChanged(snapshot("a", "b")))
        #expect(arrived.selection == ConversationID("a"))
        #expect(arrived.pendingOpen == nil)
    }

    @Test func choosingAConversationCancelsAWaitingOpen() {
        let waiting = InboxReducer.reduce(InboxState(), .openRequested(ConversationID("a")))

        #expect(InboxReducer.reduce(waiting, .selected(ConversationID("b"))).pendingOpen == nil)
    }

    private func snapshot(_ ids: String...) -> InboxSnapshot {
        InboxSnapshot(conversations: ids.map { Fixtures.conversation($0) }, isSyncing: false)
    }
}

@MainActor @Suite struct InboxViewModelTests {
    @Test func followsConversationsAndConnection() async {
        let client = FakeMessagingClient()
        let (viewModel, pump) = makeViewModel(client)
        let running = Task { await viewModel.run() }

        client.emit(.conversationUpdated(Fixtures.conversation("c1", title: "Sam")))
        client.emit(.initialSyncCompleted)

        #expect(await eventually { !viewModel.state.isSyncing })
        #expect(viewModel.state.rows.map(\.title) == ["Sam"])
        #expect(viewModel.state.banner == nil)
        running.cancel()
        pump.cancel()
    }

    @Test func showsAnInboxThatSyncedBeforeTheScreenAppeared() async {
        let client = FakeMessagingClient()
        let (viewModel, pump) = makeViewModel(client)
        client.emit(.conversationUpdated(Fixtures.conversation("c1", title: "Sam")))
        client.emit(.initialSyncCompleted)

        let running = Task { await viewModel.run() }

        #expect(await eventually { !viewModel.state.isSyncing && viewModel.state.banner == nil })
        #expect(viewModel.state.rows.map(\.title) == ["Sam"])
        running.cancel()
        pump.cancel()
    }

    @Test func aClickedAlertOpensItsConversationOnce() async {
        let client = FakeMessagingClient()
        let focus = ConversationFocus()
        let (viewModel, pump) = makeViewModel(client, focus: focus)
        client.emit(.conversationUpdated(Fixtures.conversation("c1")))
        focus.requestOpen(ConversationID("c1"))

        let running = Task { await viewModel.run() }

        #expect(await eventually { viewModel.state.selection == ConversationID("c1") })
        #expect(await eventually { focus.openRequest.value == nil })
        #expect(focus.attention.value.selectedConversation == ConversationID("c1"))
        running.cancel()
        pump.cancel()
    }

    @Test func closingTheWindowMeansNothingIsSelected() async {
        let client = FakeMessagingClient()
        let focus = ConversationFocus()
        let (viewModel, pump) = makeViewModel(client, focus: focus)
        client.emit(.conversationUpdated(Fixtures.conversation("c1")))
        let running = Task { await viewModel.run() }
        #expect(await eventually { !viewModel.state.rows.isEmpty })
        viewModel.send(.selected(ConversationID("c1")))
        #expect(focus.attention.value.selectedConversation == ConversationID("c1"))

        running.cancel()
        await running.value

        #expect(focus.attention.value.selectedConversation == nil)
        pump.cancel()
    }

    private func makeViewModel(
        _ client: FakeMessagingClient,
        focus: ConversationFocus = ConversationFocus()
    ) -> (InboxViewModel, Task<Void, Never>) {
        let session = LiveSession(client: client)
        let pump = Task { await session.run() }
        let viewModel = InboxViewModel(
            observeInbox: ObserveInbox(session: session),
            observeConnectionStatus: ObserveConnectionStatus(session: session),
            focus: focus,
            loadAvatars: LoadAvatars(client: client),
            archive: ArchiveConversation(client: client),
            delete: DeleteConversation(client: client),
            mute: MuteConversation(client: client)
        )
        return (viewModel, pump)
    }
}
