import Foundation
import MessagingApplication
import MessagingDomain
import MessagingTestSupport
@testable import Presentation
import Testing

@Suite struct InboxStateTests {
    @Test func searchMatchesTitleOrPreviewIgnoringCase() {
        var state = InboxState()
        state.conversations = [
            Fixtures.conversation("1", title: "Mum", preview: "dinner at 7?"),
            Fixtures.conversation("2", title: "Dentist", preview: "Reminder"),
        ]

        state.searchText = "DINNER"
        #expect(state.rows.map(\.id.rawValue) == ["1"])

        state.searchText = "dent"
        #expect(state.rows.map(\.id.rawValue) == ["2"])

        state.searchText = "  "
        #expect(state.rows.count == 2)
    }

    @Test func emptyOnlyOnceSyncHasFinished() {
        var state = InboxState()
        #expect(state.isEmpty == false)

        state.isSyncing = false
        #expect(state.isEmpty)
    }

    @Test(arguments: [
        (ConnectionStatus.connecting, ConnectionBanner?.some(.connecting)),
        (.phoneUnreachable, .phoneUnreachable),
        (.reconnecting, .reconnecting),
        (.online, nil),
    ])
    func bannerFollowsConnection(status: ConnectionStatus, banner: ConnectionBanner?) {
        var state = InboxState()
        state.connection = status
        #expect(state.banner == banner)
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
        var state = InboxReducer.reduce(InboxState(), .inboxChanged(snapshot("a", "b")))
        state = InboxReducer.reduce(state, .selected(ConversationID("a")))

        state = InboxReducer.reduce(state, .inboxChanged(snapshot("a")))
        #expect(state.selection == ConversationID("a"))

        state = InboxReducer.reduce(state, .inboxChanged(snapshot("b")))
        #expect(state.selection == nil)
    }

    private func snapshot(_ ids: String...) -> InboxSnapshot {
        InboxSnapshot(conversations: ids.map { Fixtures.conversation($0) }, isSyncing: false)
    }
}

@MainActor @Suite struct InboxViewModelTests {
    @Test func followsConversationsAndConnection() async {
        let client = FakeMessagingClient()
        let viewModel = InboxViewModel(
            observeInbox: ObserveInbox(client: client),
            observeConnectionStatus: ObserveConnectionStatus(client: client)
        )
        let running = Task { await viewModel.run() }
        #expect(await eventually { client.subscriberCount == 2 })

        client.emit(.conversationUpdated(Fixtures.conversation("c1", title: "Sam")))
        client.emit(.initialSyncCompleted)

        #expect(await eventually { !viewModel.state.isSyncing })
        #expect(viewModel.state.rows.map(\.title) == ["Sam"])
        #expect(viewModel.state.banner == nil)
        running.cancel()
    }
}
