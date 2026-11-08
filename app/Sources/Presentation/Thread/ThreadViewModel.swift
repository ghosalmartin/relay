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

    /// - Parameter openFile: shows an attachment's contents in the app that handles its type.
    public init(
        conversation: Conversation,
        loadHistory: LoadThreadHistory,
        observeThread: ObserveThread,
        sendText: SendText,
        markRead: MarkConversationRead,
        focus: ConversationFocus,
        loadAttachment: LoadAttachment,
        openFile: @escaping @MainActor (Data, _ mimeType: String) -> Void
    ) {
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
        }
    }

    private func followMessages(_ live: AsyncStream<Message>) async {
        for await message in live {
            apply(.messageArrived(message))
            if !message.isFromMe { await markLatestRead() }
        }
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
        case .conversationChanged(let conversation):
            apply(.conversationChanged(conversation))
        case .sendTapped:
            return Task { await sendDraft() }
        case .loadOlderTapped:
            return Task { await loadOlder() }
        case .retryHistoryTapped:
            return Task { await loadLatest() }
        case .attachmentAppeared(let attachment):
            return Task { _ = await contents(of: attachment) }
        case .attachmentTapped(let attachment):
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
        apply(.sending)
        do {
            try await sendText(text, to: conversationID)
            apply(.sent(text))
        } catch {
            apply(.sendFailed(Self.describe(error)))
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
