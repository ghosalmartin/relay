import Foundation
import MessagingApplication
import MessagingDomain
import MessagingTestSupport
@testable import Presentation
import Testing

private let file = OutgoingAttachment(data: Data("picture".utf8), fileName: "a.png", mimeType: "image/png")
private let chat = ConversationID("c1")

private func state(draft: String = "", pending: OutgoingAttachment? = nil, isSending: Bool = false) -> ThreadState {
    ThreadState(conversation: Fixtures.conversation("c1"), draft: draft, isSending: isSending, pendingAttachments: pending.map { [$0] } ?? [])
}

@Suite struct ThreadPendingFileTests {
    @Test func aFileCanBeSentWithoutAnyText() {
        #expect(state(pending: file).canSend)
        #expect(!state().canSend)
    }

    @Test func nothingCanBeSentTwiceAtOnce() {
        #expect(!state(pending: file, isSending: true).canSend)
    }

    @Test func aSecondFileJoinsTheFirst() {
        let other = OutgoingAttachment(data: Data(), fileName: "b.png", mimeType: "image/png")

        #expect(ThreadReducer.reduce(state(pending: file), .fileAdded(other)).pendingAttachments == [file, other])
    }

    @Test func theSameFileIsOnlyAddedOnce() {
        #expect(ThreadReducer.reduce(state(pending: file), .fileAdded(file)).pendingAttachments == [file])
    }

    @Test func thereIsALimitOnFilesWaiting() {
        let full = (0..<ThreadState.maximumPendingFiles).reduce(state()) { waiting, index in
            ThreadReducer.reduce(waiting, .fileAdded(OutgoingAttachment(data: Data(), fileName: "\(index).png", mimeType: "image/png")))
        }

        let result = ThreadReducer.reduce(full, .fileAdded(file))

        #expect(result.pendingAttachments.count == ThreadState.maximumPendingFiles)
        #expect(result.sendError?.contains("up to 10") == true)
    }

    @Test func theFileBeingSentCannotBeSwappedOrRemoved() {
        let other = OutgoingAttachment(data: Data(), fileName: "b.png", mimeType: "image/png")
        let sending = state(pending: file, isSending: true)

        #expect(ThreadReducer.reduce(sending, .fileAdded(other)).pendingAttachments == [file])
        #expect(ThreadReducer.reduce(sending, .fileRemoved(file)).pendingAttachments == [file])
    }

    @Test func anOversizedFileIsRefusedInPlainWords() {
        let huge = OutgoingAttachment(data: Data(count: OutgoingAttachment.maximumByteCount + 1), fileName: "b.mov", mimeType: "video/mp4")

        let result = ThreadReducer.reduce(state(), .fileAdded(huge))

        #expect(result.pendingAttachments.isEmpty)
        #expect(result.sendError?.contains("too big") == true)
    }

    @Test func aCaptionTypedDuringTheSendIsKept() {
        let result = ThreadReducer.reduce(state(draft: "newer", pending: file, isSending: true), .fileSent(file, caption: "older"))

        #expect(result.draft == "newer")
        #expect(result.pendingAttachments.isEmpty)
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
            sendAttachment: SendAttachment(client: client),
            observeConnectionStatus: ObserveConnectionStatus(session: LiveSession(client: client)),
            sendReaction: SendReaction(client: client),
            deleteMessage: DeleteMessage(client: client)
        )
    }

    @Test func theDraftGoesOutAsTheCaptionAndBothClear() async {
        let client = FakeMessagingClient()
        let viewModel = makeViewModel(client)
        viewModel.send(.fileRead(file))
        viewModel.send(.draftChanged("  Look  "))

        await viewModel.send(.sendTapped).value

        #expect(client.calls == [.sendAttachment(file, caption: "Look", chat)])
        #expect(viewModel.state.pendingAttachments.isEmpty)
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
        client.stubSendAttachmentError(.notPaired)
        let viewModel = makeViewModel(client)
        viewModel.send(.fileRead(file))

        await viewModel.send(.sendTapped).value

        #expect(viewModel.state.pendingAttachments == [file])
        #expect(viewModel.state.sendError != nil)
    }

    @Test func severalFilesGoOutInOrderWithTheCaptionOnTheFirst() async {
        let client = FakeMessagingClient()
        let second = OutgoingAttachment(data: Data("two".utf8), fileName: "b.png", mimeType: "image/png")
        let viewModel = makeViewModel(client)
        viewModel.send(.fileRead(file))
        viewModel.send(.fileRead(second))
        viewModel.send(.draftChanged("Look"))

        await viewModel.send(.sendTapped).value

        #expect(client.calls == [.sendAttachment(file, caption: "Look", chat), .sendAttachment(second, caption: nil, chat)])
        #expect(viewModel.state.pendingAttachments.isEmpty)
        #expect(!viewModel.state.isSending)
    }

    @Test func aClipPlaysInTheBubbleInsteadOfOpeningAnotherApp() async {
        let client = FakeMessagingClient()
        client.stubAttachment(.success(Data("clip".utf8)))
        let clip = MessagingDomain.Attachment(id: "v", fileName: "a.mp4", mimeType: "video/mp4", byteCount: 4)
        let viewModel = makeViewModel(client)

        await viewModel.send(.attachmentTapped(clip)).value

        #expect(viewModel.state.attachments["v"] == .loaded(Data("clip".utf8)))
    }

    @Test func anUnreadableFileIsExplained() {
        let viewModel = makeViewModel(FakeMessagingClient())

        viewModel.send(.fileRead(nil))

        #expect(viewModel.state.sendError == "Couldn't read that file.")
    }
}
