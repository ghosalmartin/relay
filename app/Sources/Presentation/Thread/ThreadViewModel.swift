import Foundation
import MessagingApplication
import MessagingDomain
import Observation

@MainActor @Observable
public final class ThreadViewModel {
    public private(set) var state: ThreadState

    private let loadHistory: LoadThreadHistory
    private let observeThread: ObserveThread
    private let sendText: SendText
    private let markRead: MarkConversationRead
    private let focus: ConversationFocus
    private let loadAttachment: LoadAttachment
    private let openFile: @MainActor (Data, _ mimeType: String) -> Void
    private let sendAttachment: SendAttachment
    private let observeConnectionStatus: ObserveConnectionStatus
    private let sendReaction: SendReaction
    private let deleteMessage: DeleteMessage

    /// - Parameter openFile: shows an attachment's contents in the app that handles its type.
    public init(
        conversation: Conversation,
        loadHistory: LoadThreadHistory,
        observeThread: ObserveThread,
        sendText: SendText,
        markRead: MarkConversationRead,
        focus: ConversationFocus,
        loadAttachment: LoadAttachment,
        openFile: @escaping @MainActor (Data, _ mimeType: String) -> Void,
        sendAttachment: SendAttachment,
        observeConnectionStatus: ObserveConnectionStatus,
        sendReaction: SendReaction,
        deleteMessage: DeleteMessage
    ) {
        self.observeConnectionStatus = observeConnectionStatus
        self.sendReaction = sendReaction
        self.deleteMessage = deleteMessage
        self.sendAttachment = sendAttachment
        self.state = ThreadState(conversation: conversation)
        self.loadHistory = loadHistory
        self.observeThread = observeThread
        self.sendText = sendText
        self.markRead = markRead
        self.focus = focus
        self.loadAttachment = loadAttachment
        self.openFile = openFile
    }

    private var conversationID: ConversationID { state.conversation.id }

    /// Loads the latest page, then follows new messages until the view goes away.
    /// Call from the view's `.task(id: conversation.id)`.
    public func run() async {
        let live = observeThread(conversationID)   // subscribe first so nothing slips between load and follow
        await loadLatest()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.followMessages(live) }
            group.addTask { await self.markReadWhenViewed() }
            group.addTask { await self.followConnection() }
        }
    }

    private func followMessages(_ live: AsyncStream<Message>) async {
        for await message in live {
            apply(.messageArrived(message))
            if !message.isFromMe { await markLatestRead() }
        }
    }

    private func followConnection() async {
        for await status in observeConnectionStatus() {
            let phoneReturned = state.isPhoneReturn(to: status)
            apply(.connectionChanged(status))
            if phoneReturned { await catchUp() }
        }
    }

    /// Quietly, because messages already on screen shouldn't give way to a spinner or an error.
    private func catchUp() async {
        guard !state.messages.isEmpty else { return await loadLatest() }
        guard let page = try? await loadHistory(conversationID) else { return }
        apply(.caughtUp(page))
        await markLatestRead()
    }

    /// Catches up on anything that arrived while the user was in another app.
    private func markReadWhenViewed() async {
        for await attention in focus.attention.values() where attention.visibleConversation == conversationID {
            await markLatestRead()
        }
    }

    @discardableResult
    public func send(_ intent: ThreadIntent) -> Task<Void, Never> {
        switch intent {
        case .draftChanged(let text):
            apply(.draftChanged(text))
        case .sendErrorDismissed:
            apply(.sendErrorDismissed)
        case .waitingDismissed:
            apply(.waitingDismissed)
        case .conversationChanged(let conversation):
            apply(.conversationChanged(conversation))
        case .fileRead(let file):
            apply(file.map(ThreadMutation.fileAdded) ?? .sendFailed("Couldn't read that file."))
        case .fileRemoved(let file):
            apply(.fileRemoved(file))
        case .replyTapped(let id):
            apply(.replyStarted(id))
        case .replyCancelled:
            apply(.replyCancelled)
        case .reactionChosen(let emoji, let id):
            return Task { await react(emoji, to: id) }
        case .deleteTapped(let id):
            apply(.deleteRequested(id))
        case .deleteCancelled:
            apply(.deleteRequested(nil))
        case .deleteConfirmed:
            return Task { await deleteConfirmedMessage() }
        case .sendTapped:
            return Task { await sendDraft() }
        case .loadOlderTapped:
            return Task { await loadOlder() }
        case .retryHistoryTapped:
            return Task { await loadLatest() }
        case .attachmentAppeared(let attachment):
            return Task { _ = await contents(of: attachment) }
        case .attachmentTapped(let attachment):
            return Task {
                if attachment.playsInline {
                    _ = await contents(of: attachment)
                } else {
                    await open(attachment)
                }
            }
        case .attachmentOpenTapped(let attachment):
            return Task { await open(attachment) }
        }
        return Task {}
    }

    /// Nil if it failed, or if another caller is already fetching it.
    private func contents(of attachment: Attachment) async -> Data? {
        switch state.attachments[attachment.id] {
        case .loaded(let data): return data
        case .loading: return nil
        case .failed, nil: break
        }
        apply(.attachmentChanged(id: attachment.id, .loading))
        do {
            let data = try await loadAttachment(attachment)
            apply(.attachmentChanged(id: attachment.id, .loaded(data)))
            return data
        } catch {
            apply(.attachmentChanged(id: attachment.id, .failed))
            return nil
        }
    }

    private func open(_ attachment: Attachment) async {
        guard attachment.canOpen, let data = await contents(of: attachment) else { return }
        openFile(data, attachment.mimeType)
    }

    private func loadLatest() async {
        apply(.historyLoading)
        do {
            apply(.historyLoaded(try await loadHistory(conversationID)))
            await markLatestRead()
        } catch {
            apply(.historyFailed(Self.describe(error)))
        }
    }

    private func loadOlder() async {
        guard state.canLoadOlder, let cursor = state.olderCursor else { return }
        apply(.olderLoading)
        do {
            apply(.olderLoaded(try await loadHistory(conversationID, before: cursor)))
        } catch {
            apply(.olderFailed)
        }
    }

    private func sendDraft() async {
        guard state.canSend else { return }
        let text = state.draft
        let files = state.pendingAttachments
        let reply = state.replyTarget
        apply(.sending)
        if files.isEmpty {
            await sendTyped(text, replyingTo: reply)
        } else {
            await sendFiles(files, caption: text, replyingTo: reply)
        }
    }

    private func sendTyped(_ text: String, replyingTo reply: MessageID?) async {
        do {
            try await sendText(text, to: conversationID, replyingTo: reply)
            apply(.sent(text))
        } catch .messaging(.phoneUnreachable) {
            apply(.waitingForPhone(WaitingMessage(text: SendText.sendableText(from: text) ?? text, hasFile: false), typed: text, file: nil))
        } catch {
            apply(.sendFailed(Self.describe(error)))
        }
    }

    /// One message per file, as libgm's own bridge sends them. The first carries the caption and the reply.
    /// Stops at the first file that doesn't get through; the rest stay in the composer.
    private func sendFiles(_ files: [OutgoingAttachment], caption: String, replyingTo reply: MessageID?) async {
        for (index, file) in files.enumerated() {
            let isFirst = index == 0
            let thisCaption = isFirst ? caption : ""
            do {
                try await sendAttachment(file, caption: thisCaption, to: conversationID, replyingTo: isFirst ? reply : nil)
                apply(.fileSent(file, caption: thisCaption))
            } catch .phoneUnreachable {
                let waiting = WaitingMessage(text: SendText.sendableText(from: thisCaption) ?? "", hasFile: true)
                return apply(.waitingForPhone(waiting, typed: thisCaption, file: file))
            } catch {
                return apply(.sendFailed(Self.describe(error)))
            }
        }
    }

    private func react(_ emoji: String, to message: MessageID) async {
        do {
            try await sendReaction(emoji, to: message, in: conversationID)
        } catch {
            apply(.actionFailed(Self.describe(error)))
        }
    }

    private func deleteConfirmedMessage() async {
        guard let id = state.confirmingDelete else { return }
        apply(.deleteRequested(nil))
        do {
            try await deleteMessage(id)
            apply(.messageRemoved(id))
        } catch {
            apply(.actionFailed(Self.describe(error)))
        }
    }

    private func markLatestRead() async {
        // Read receipts tell the sender you've seen it, so only send them when that's true.
        guard focus.isVisible(conversationID), let latest = state.newestIncomingMessage else { return }
        try? await markRead(conversationID, upTo: latest.id)   // best effort; the next message retries
    }

    private func apply(_ mutation: ThreadMutation) {
        state = ThreadReducer.reduce(state, mutation)
    }

    static func describe(_ error: any Error) -> String {
        switch error {
        case SendText.Failure.emptyMessage: "There's nothing to send."
        case SendText.Failure.messaging(let error): describe(error)
        case MessagingError.phoneUnreachable: "Your phone isn't responding. Check it's on and connected."
        case MessagingError.notPaired: "This Mac isn't paired with your phone any more."
        case MessagingError.conversationNotFound: "This conversation is no longer on your phone."
        case MessagingError.backend(let message): message
        default: "Something went wrong."
        }
    }
}
