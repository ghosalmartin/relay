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

    public init(
        conversation: Conversation,
        loadHistory: LoadThreadHistory,
        observeThread: ObserveThread,
        sendText: SendText,
        markRead: MarkConversationRead
    ) {
        self.state = ThreadState(conversation: conversation)
        self.loadHistory = loadHistory
        self.observeThread = observeThread
        self.sendText = sendText
        self.markRead = markRead
    }

    private var conversationID: ConversationID { state.conversation.id }

    /// Loads the latest page, then follows new messages until the view goes away.
    /// Call from the view's `.task(id: conversation.id)`.
    public func run() async {
        let live = observeThread(conversationID)   // subscribe first so nothing slips between load and follow
        await loadLatest()
        for await message in live {
            apply(.messageArrived(message))
            if !message.isFromMe { await markLatestRead() }
        }
    }

    @discardableResult
    public func send(_ intent: ThreadIntent) -> Task<Void, Never> {
        switch intent {
        case .draftChanged(let text):
            apply(.draftChanged(text))
        case .sendErrorDismissed:
            apply(.sendErrorDismissed)
        case .sendTapped:
            return Task { await sendDraft() }
        case .loadOlderTapped:
            return Task { await loadOlder() }
        case .retryHistoryTapped:
            return Task { await loadLatest() }
        }
        return Task {}
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
        apply(.sending)
        do {
            try await sendText(state.draft, to: conversationID)
            apply(.sent)
        } catch {
            apply(.sendFailed(Self.describe(error)))
        }
    }

    private func markLatestRead() async {
        guard let latest = state.newestIncomingMessage else { return }
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
