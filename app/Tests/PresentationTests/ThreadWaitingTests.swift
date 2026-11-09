import Foundation
import MessagingApplication
import MessagingDomain
import MessagingTestSupport
@testable import Presentation
import Testing

private let chat = ConversationID("c1")
private let waitingText = WaitingMessage(text: "on my way", hasFile: false)

@MainActor
@Suite struct ThreadWaitingTests {
    private func make(_ client: FakeMessagingClient) -> ThreadViewModel {
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

    private func own(_ id: String, text: String, file: Bool = false) -> Message {
        let picture = MessagingDomain.Attachment(id: id, fileName: "a.png", mimeType: "image/png", byteCount: nil)
        return Message(
            id: MessageID(id),
            conversationID: chat,
            sender: .me,
            sentAt: Date(timeIntervalSince1970: 0),
            parts: (text.isEmpty ? [] : [.text(text)]) + (file ? [.attachment(picture)] : []),
            status: .sent
        )
    }

    private func waiting(_ messages: WaitingMessage...) -> ThreadState {
        ThreadState(conversation: Fixtures.conversation("c1"), waitingMessages: messages)
    }

    @Test func aSendThePhoneHasNotAnsweredIsWaitingAndCannotBeResentByAccident() async {
        let client = FakeMessagingClient()
        client.stubSend(throwing: .phoneUnreachable)
        let viewModel = make(client)
        viewModel.send(.draftChanged("  on my way "))

        await viewModel.send(.sendTapped).value

        #expect(viewModel.state.sendError == nil)
        #expect(viewModel.state.draft == "")
        #expect(!viewModel.state.isSending)
        #expect(viewModel.state.waitingMessages == [waitingText])
        #expect(viewModel.state.waitingNotice != nil)
    }

    @Test func aWaitingFileLeavesTheComposerAndTheFilesBehindItStay() async {
        let client = FakeMessagingClient()
        client.stubSendAttachmentError(.phoneUnreachable)
        let first = OutgoingAttachment(data: Data("1".utf8), fileName: "a.png", mimeType: "image/png")
        let second = OutgoingAttachment(data: Data("2".utf8), fileName: "b.png", mimeType: "image/png")
        let viewModel = make(client)
        viewModel.send(.fileRead(first))
        viewModel.send(.fileRead(second))
        viewModel.send(.draftChanged("Look"))

        await viewModel.send(.sendTapped).value

        #expect(viewModel.state.waitingMessages == [WaitingMessage(text: "Look", hasFile: true)])
        #expect(viewModel.state.pendingAttachments == [second])
        #expect(viewModel.state.draft == "")
        #expect(!viewModel.state.isSending)
    }

    @Test func nothingIsWaitingWithoutAnUnansweredSend() {
        #expect(ThreadState(conversation: Fixtures.conversation("c1")).waitingNotice == nil)
    }

    @Test func thePhoneReportingTheMessageEndsTheWait() {
        let state = ThreadReducer.reduce(waiting(waitingText), .messageArrived(own("m1", text: "on my way")))
        #expect(state.waitingMessages.isEmpty)
    }

    @Test func theMessageCanTurnUpWhenTheChatCatchesUp() {
        let page = MessagePage(messages: [own("m1", text: "on my way")], olderCursor: nil)
        #expect(ThreadReducer.reduce(waiting(waitingText), .caughtUp(page)).waitingMessages.isEmpty)
        #expect(ThreadReducer.reduce(waiting(waitingText), .historyLoaded(page)).waitingMessages.isEmpty)
    }

    @Test func oneMessageEndsOnlyOneOfTwoIdenticalWaits() {
        let state = ThreadReducer.reduce(waiting(waitingText, waitingText), .messageArrived(own("m1", text: "on my way")))
        #expect(state.waitingMessages == [waitingText])
    }

    @Test func aMessageAlreadyInTheChatDoesNotEndAWait() {
        let old = own("m1", text: "on my way")
        let state = ThreadState(conversation: Fixtures.conversation("c1"), messages: [old], waitingMessages: [waitingText])
        #expect(ThreadReducer.reduce(state, .messageArrived(old)).waitingMessages == [waitingText])
    }

    @Test func theSameWordsFromSomeoneElseDoNotEndAWait() {
        let theirs = Fixtures.message("m1", text: "on my way")
        #expect(ThreadReducer.reduce(waiting(waitingText), .messageArrived(theirs)).waitingMessages == [waitingText])
    }

    @Test func aFileOnlyMatchesAMessageCarryingAFile() {
        let file = WaitingMessage(text: "", hasFile: true)
        #expect(ThreadReducer.reduce(waiting(file), .messageArrived(own("m1", text: "", file: true))).waitingMessages.isEmpty)
        #expect(ThreadReducer.reduce(waiting(file), .messageArrived(own("m2", text: ""))).waitingMessages == [file])
    }

    @Test func theNoticeCanBeDismissed() {
        #expect(ThreadReducer.reduce(waiting(waitingText), .waitingDismissed).waitingNotice == nil)
    }
}
