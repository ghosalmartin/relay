import MessagingApplication
import MessagingDomain
import MessagingTestSupport
@testable import Presentation
import Testing

private let chat = ConversationID("c1")

@MainActor
@Suite struct InboxActionsTests {
    private func make(_ client: FakeMessagingClient) -> InboxViewModel {
        let session = LiveSession(client: client)
        return InboxViewModel(
            observeInbox: ObserveInbox(session: session),
            observeConnectionStatus: ObserveConnectionStatus(session: session),
            focus: ConversationFocus(),
            loadAvatars: LoadAvatars(client: client),
            archive: ArchiveConversation(client: client),
            delete: DeleteConversation(client: client),
            mute: MuteConversation(client: client)
        )
    }

    @Test func archivingAsksThePhone() async {
        let client = FakeMessagingClient()

        await make(client).send(.archiveTapped(chat)).value

        #expect(client.calls == [.archive(chat)])
    }

    @Test(arguments: [true, false])
    func mutingAsksThePhone(isMuted: Bool) async {
        let client = FakeMessagingClient()

        await make(client).send(.muteTapped(chat, isMuted: isMuted)).value

        #expect(client.calls == [.setMuted(isMuted, chat)])
    }

    @Test func deletingAConversationAsksFirst() async {
        let client = FakeMessagingClient()
        let viewModel = make(client)

        viewModel.send(.deleteTapped(chat))
        #expect(viewModel.state.confirmingDelete == chat)
        #expect(client.calls.isEmpty)

        await viewModel.send(.deleteConfirmed).value
        #expect(client.calls == [.deleteConversation(chat)])
        #expect(viewModel.state.confirmingDelete == nil)
    }

    @Test func aFailureIsExplained() async {
        let client = FakeMessagingClient()
        client.stubAction(throwing: .phoneUnreachable)
        let viewModel = make(client)

        await viewModel.send(.archiveTapped(chat)).value
        #expect(viewModel.state.actionError?.contains("isn't responding") == true)

        viewModel.send(.actionErrorDismissed)
        #expect(viewModel.state.actionError == nil)
    }

    @Test func theComposeSheetOpensAndCloses() {
        let viewModel = make(FakeMessagingClient())

        viewModel.send(.composeTapped)
        #expect(viewModel.state.isComposing)

        viewModel.send(.composeDismissed)
        #expect(!viewModel.state.isComposing)
    }
}
