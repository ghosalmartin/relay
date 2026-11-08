import Foundation
import MessagingApplication
import MessagingDomain
import MessagingTestSupport
@testable import Presentation
import Testing

private typealias Attachment = MessagingDomain.Attachment     // Testing has one too

private let photo = Attachment(id: "a1", fileName: "cat.jpg", mimeType: "image/jpeg", byteCount: 2048)

private func message(_ id: String, parts: [MessagePart], status: DeliveryStatus = .received,
                     reactions: [Reaction] = [], replyTo: MessageID? = nil) -> Message {
    Message(id: MessageID(id), conversationID: ConversationID("c1"), sender: .participant(ParticipantID("p1")),
            sentAt: Date(timeIntervalSince1970: 0), parts: parts, status: status, reactions: reactions, replyTo: replyTo)
}

private func bubble(_ id: String, in messages: [Message]) throws -> MessageBubble {
    let items = ThreadLayout.items(for: messages, in: Fixtures.conversation("c1"), calendar: .current)
    let bubbles = items.compactMap { item -> MessageBubble? in
        if case .bubble(let bubble) = item { return bubble }
        return nil
    }
    return try #require(bubbles.first { $0.id == MessageID(id) })
}

@Suite struct ThreadBubbleContentTests {
    @Test func reactionsReachTheBubble() throws {
        let reacted = message("m1", parts: [.text("hi")], reactions: [Reaction(emoji: "👍", count: 2)])

        #expect(try bubble("m1", in: [reacted]).reactions == [Reaction(emoji: "👍", count: 2)])
    }

    @Test func aReplyPreviewsTheOriginalText() throws {
        let original = message("m1", parts: [.text("Pub at 7?")])
        let reply = message("m2", parts: [.text("Yes")], replyTo: MessageID("m1"))

        #expect(try bubble("m2", in: [original, reply]).replyPreview == "Pub at 7?")
    }

    @Test func aReplyToAPictureSaysSo() throws {
        let original = message("m1", parts: [.attachment(photo)])
        let reply = message("m2", parts: [.text("Cute")], replyTo: MessageID("m1"))

        #expect(try bubble("m2", in: [original, reply]).replyPreview == "Attachment")
    }

    @Test func aReplyToSomethingNotLoadedStillShowsItIsAReply() throws {
        let reply = message("m2", parts: [.text("Yes")], replyTo: MessageID("older"))

        #expect(try bubble("m2", in: [reply]).replyPreview == "Replying to an earlier message")
    }

    @Test func aReactionShowsItsCountOnlyWhenMoreThanOnePersonUsedIt() {
        #expect(Reaction(emoji: "👍", count: 1).displayText == "👍")
        #expect(Reaction(emoji: "👍", count: 3).displayText == "👍 3")
    }

    @Test func aFileThatFailedToLoadShowsAWarningIcon() {
        let document = Attachment(id: "a2", fileName: "a.pdf", mimeType: "application/pdf", byteCount: nil)

        #expect(document.symbolName(showing: .failed) == "exclamationmark.triangle")
        #expect(document.symbolName(showing: nil) == "doc.richtext")
    }

    @Test func onlyAPictureCountsAsHavingOne() throws {
        let document = Attachment(id: "a2", fileName: "a.pdf", mimeType: "application/pdf", byteCount: nil)

        #expect(try bubble("m1", in: [message("m1", parts: [.attachment(photo), .text("Look")])]).hasPicture)
        #expect(try !bubble("m1", in: [message("m1", parts: [.attachment(document)])]).hasPicture)
    }

    @Test func aDeletedMessageSaysSoInsteadOfItsContent() throws {
        let deleted = message("m1", parts: [.text("oops")], status: .deleted)

        #expect(try bubble("m1", in: [deleted]).placeholder == "This message was deleted.")
    }

    @Test func aMessageWithNothingToDrawIsNotABlankBubble() throws {
        #expect(try bubble("m1", in: [message("m1", parts: [])]).placeholder == "This kind of message isn't supported yet.")
    }

    @Test func ordinaryMessagesHaveNoPlaceholder() throws {
        #expect(try bubble("m1", in: [message("m1", parts: [.text("hi")])]).placeholder == nil)
    }
}

@Suite struct LinkedTextTests {
    private func links(in text: String) -> [URL] {
        LinkedText.attributed(text).runs.compactMap(\.link)
    }

    @Test func webAddressesBecomeLinks() {
        #expect(links(in: "see https://example.com now") == [URL(string: "https://example.com")!])
    }

    @Test func plainTextHasNoLinks() {
        #expect(links(in: "no address here").isEmpty)
    }

    @Test func onlyWebPagesAreClickable() {
        #expect(links(in: "file:///etc/passwd").isEmpty)
    }

    @Test func theWordingIsUnchanged() {
        #expect(String(LinkedText.attributed("see https://example.com now").characters) == "see https://example.com now")
    }
}

@Suite struct AttachmentDisplayTests {
    private func attachment(_ mimeType: String, name: String = "") -> Attachment {
        Attachment(id: "a", fileName: name, mimeType: mimeType, byteCount: nil)
    }

    @Test(arguments: ["image/jpeg", "video/mp4", "audio/ogg", "application/pdf"])
    func harmlessKindsCanBeOpened(mimeType: String) {
        #expect(attachment(mimeType).canOpen)
    }

    @Test(arguments: ["application/x-msdownload", "application/zip", "text/html", "image/svg+xml", ""])
    func anythingThatCouldRunCodeCannotBeOpened(mimeType: String) {
        #expect(!attachment(mimeType).canOpen)
    }

    @Test func anUnnamedPictureGetsAName() {
        #expect(attachment("image/png").displayName == "Photo")
        #expect(attachment("image/png", name: "cat.png").displayName == "cat.png")
    }
}

@MainActor
@Suite struct ThreadAttachmentTests {
    private let picture = Data("picture".utf8)

    private final class Opened {
        var files: [(Data, String)] = []
    }

    private func makeViewModel(_ client: FakeMessagingClient, opened: Opened = Opened()) -> ThreadViewModel {
        ThreadViewModel(
            conversation: Fixtures.conversation("c1"),
            loadHistory: LoadThreadHistory(client: client),
            observeThread: ObserveThread(client: client),
            sendText: SendText(client: client),
            markRead: MarkConversationRead(client: client),
            focus: ConversationFocus(),
            loadAttachment: LoadAttachment(client: client),
            openFile: { opened.files.append(($0, $1)) }
        )
    }

    @Test func aPictureIsFetchedOnceHoweverOftenItAppears() async {
        let client = FakeMessagingClient()
        client.stubAttachment(.success(picture))
        let viewModel = makeViewModel(client)

        let first = viewModel.send(.attachmentAppeared(photo))
        let second = viewModel.send(.attachmentAppeared(photo))
        await first.value
        await second.value
        await viewModel.send(.attachmentAppeared(photo)).value

        #expect(viewModel.state.attachments["a1"] == .loaded(picture))
        #expect(client.calls == [.attachmentData(photo)])
    }

    @Test func aFailedPictureCanBeRetried() async {
        let client = FakeMessagingClient()
        client.stubAttachment(.failure(.phoneUnreachable))
        let viewModel = makeViewModel(client)

        await viewModel.send(.attachmentAppeared(photo)).value
        #expect(viewModel.state.attachments["a1"] == .failed)

        client.stubAttachment(.success(picture))
        await viewModel.send(.attachmentAppeared(photo)).value
        #expect(viewModel.state.attachments["a1"] == .loaded(picture))
    }

    @Test func tappingOpensTheFileWithItsType() async {
        let client = FakeMessagingClient()
        client.stubAttachment(.success(picture))
        let opened = Opened()
        let viewModel = makeViewModel(client, opened: opened)

        await viewModel.send(.attachmentTapped(photo)).value

        #expect(opened.files.map(\.0) == [picture])
        #expect(opened.files.map(\.1) == ["image/jpeg"])
    }

    @Test func aFileThatCouldRunCodeIsNeverFetchedOrOpened() async {
        let client = FakeMessagingClient()
        let opened = Opened()
        let viewModel = makeViewModel(client, opened: opened)
        let program = Attachment(id: "x", fileName: "invoice.pdf", mimeType: "application/x-msdownload", byteCount: nil)

        await viewModel.send(.attachmentTapped(program)).value

        #expect(opened.files.isEmpty)
        #expect(client.calls.isEmpty)
    }

    @Test func aFailedDownloadOpensNothing() async {
        let client = FakeMessagingClient()
        client.stubAttachment(.failure(.phoneUnreachable))
        let opened = Opened()

        await makeViewModel(client, opened: opened).send(.attachmentTapped(photo)).value

        #expect(opened.files.isEmpty)
    }
}
