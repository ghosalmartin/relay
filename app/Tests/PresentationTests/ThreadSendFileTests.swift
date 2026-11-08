import Foundation
import MessagingApplication
import MessagingDomain
import MessagingTestSupport
@testable import Presentation
import Testing

private let file = OutgoingAttachment(data: Data("picture".utf8), fileName: "a.png", mimeType: "image/png")
private let chat = ConversationID("c1")

private func state(draft: String = "", pending: OutgoingAttachment? = nil, isSending: Bool = false) -> ThreadState {
    ThreadState(conversation: Fixtures.conversation("c1"), draft: draft, isSending: isSending, pendingAttachment: pending)
}

@Suite struct ThreadPendingFileTests {
    @Test func aFileCanBeSentWithoutAnyText() {
        #expect(state(pending: file).canSend)
        #expect(!state().canSend)
    }

    @Test func nothingCanBeSentTwiceAtOnce() {
        #expect(!state(pending: file, isSending: true).canSend)
    }

    @Test func aNewFileReplacesTheOneWaiting() {
        let other = OutgoingAttachment(data: Data(), fileName: "b.png", mimeType: "image/png")

        #expect(ThreadReducer.reduce(state(pending: file), .fileAdded(other)).pendingAttachment == other)
    }

    @Test func theFileBeingSentCannotBeSwappedOrRemoved() {
        let other = OutgoingAttachment(data: Data(), fileName: "b.png", mimeType: "image/png")
        let sending = state(pending: file, isSending: true)

        #expect(ThreadReducer.reduce(sending, .fileAdded(other)).pendingAttachment == file)
        #expect(ThreadReducer.reduce(sending, .fileRemoved).pendingAttachment == file)
    }

    @Test func anOversizedFileIsRefusedInPlainWords() {
        let huge = OutgoingAttachment(data: Data(count: OutgoingAttachment.maximumByteCount + 1), fileName: "b.mov", mimeType: "video/mp4")

        let result = ThreadReducer.reduce(state(), .fileAdded(huge))

        #expect(result.pendingAttachment == nil)
        #expect(result.sendError?.contains("too big") == true)
    }

    @Test func aCaptionTypedDuringTheSendIsKept() {
        let result = ThreadReducer.reduce(state(draft: "newer", pending: file, isSending: true), .fileSent(caption: "older"))

        #expect(result.draft == "newer")
        #expect(result.pendingAttachment == nil)
        #expect(!result.isSending)
    }
}

@MainActor
@Suite struct ThreadSendFileTests {
    private func makeViewModel(_ client: FakeMessagingClient) -> ThreadViewModel {
        ThreadViewModel(
            conversation: Fixtures.conversation("c1"),
            loadHistory: LoadThreadHistory(client: client),
            observeThread: ObserveThread(client: client),
            sendText: SendText(client: client),
            markRead: MarkConversationRead(client: client),
            focus: ConversationFocus(),
            loadAttachment: LoadAttachment(client: client),
            openFile: { _, _ in },
            sendAttachment: SendAttachment(client: client)
        )
    }

    @Test func theDraftGoesOutAsTheCaptionAndBothClear() async {
        let client = FakeMessagingClient()
        let viewModel = makeViewModel(client)
        viewModel.send(.fileRead(file))
        viewModel.send(.draftChanged("  Look  "))

        await viewModel.send(.sendTapped).value

        #expect(client.calls == [.sendAttachment(file, caption: "Look", chat)])
        #expect(viewModel.state.pendingAttachment == nil)
        #expect(viewModel.state.draft.isEmpty)
    }

    @Test func aBlankDraftMeansNoCaption() async {
        let client = FakeMessagingClient()
        let viewModel = makeViewModel(client)
        viewModel.send(.fileRead(file))

        await viewModel.send(.sendTapped).value

        #expect(client.calls == [.sendAttachment(file, caption: nil, chat)])
    }

    @Test func aFailedSendKeepsTheFileToTryAgain() async {
        let client = FakeMessagingClient()
        client.stubSendAttachmentError(.phoneUnreachable)
        let viewModel = makeViewModel(client)
        viewModel.send(.fileRead(file))

        await viewModel.send(.sendTapped).value

        #expect(viewModel.state.pendingAttachment == file)
        #expect(viewModel.state.sendError != nil)
    }

    @Test func anUnreadableFileIsExplained() {
        let viewModel = makeViewModel(FakeMessagingClient())

        viewModel.send(.fileRead(nil))

        #expect(viewModel.state.sendError == "Couldn't read that file.")
    }
}
