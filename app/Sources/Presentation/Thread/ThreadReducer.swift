import MessagingDomain

public enum ThreadReducer: Reducer {
    public static func reduce(_ state: ThreadState, _ mutation: ThreadMutation) -> ThreadState {
        switch mutation {
        case .historyLoading:
            state.with(history: .loading)
        case .historyLoaded(let page):
            state.with(messages: merge(page.messages, into: state.messages), olderCursor: .some(page.olderCursor), history: .loaded, waitingMessages: stillWaiting(after: page.messages, in: state))
        case .historyFailed(let message):
            state.with(history: .failed(message: message))
        case .olderLoading:
            state.with(isLoadingOlder: true)
        case .olderLoaded(let page):
            state.with(messages: merge(page.messages, into: state.messages), olderCursor: .some(page.olderCursor), isLoadingOlder: false)
        case .olderFailed:
            state.with(isLoadingOlder: false)
        case .messageArrived(let message):
            state.with(messages: merge([message], into: state.messages), waitingMessages: stillWaiting(after: [message], in: state))
        case .draftChanged(let text):
            state.with(draft: text)
        case .sending:
            state.with(isSending: true, sendError: .some(nil))
        case .sent(let text):
            state.with(draft: state.draft == text ? "" : state.draft, isSending: false, replyTarget: .some(nil))
        case .sendFailed(let message):
            state.with(isSending: false, sendError: .some(message))
        case .sendErrorDismissed:
            state.with(sendError: .some(nil))
        case .waitingDismissed:
            state.with(waitingMessages: [])
        case .waitingForPhone(let waiting, let typed, let file):
            reduce(state, file.map { .fileSent($0, caption: typed) } ?? .sent(typed))
                .with(isSending: false, waitingMessages: state.waitingMessages + [waiting])
        case .conversationChanged(let conversation):
            state.with(conversation: conversation)
        case .attachmentChanged(let id, let content):
            state.with(attachments: state.attachments.merging([id: content]) { _, updated in updated })
        case .fileAdded where state.isSending:
            state     // what's on its way out stays what the user sees until it has gone
        case .fileAdded(let file) where file.data.count > OutgoingAttachment.maximumByteCount:
            state.with(sendError: .some("That file is too big to send. The limit is 100 MB."))
        case .fileAdded(let file) where state.pendingAttachments.contains(file):
            state
        case .fileAdded where state.pendingAttachments.count >= ThreadState.maximumPendingFiles:
            state.with(sendError: .some("You can send up to \(ThreadState.maximumPendingFiles) files at a time."))
        case .fileAdded(let file):
            state.with(pendingAttachments: state.pendingAttachments + [file])
        case .fileRemoved where state.isSending:
            state
        case .fileRemoved(let file):
            state.with(pendingAttachments: state.pendingAttachments.filter { $0 != file })
        case .fileSent(let file, let caption):
            afterSending(file, caption: caption, from: state)
        case .connectionChanged(let status):
            state.with(connection: status)
        case .caughtUp(let page):
            state.with(messages: merge(page.messages, into: state.messages), history: .loaded, waitingMessages: stillWaiting(after: page.messages, in: state))
        case .replyStarted(let id):
            state.with(replyTarget: .some(id))
        case .replyCancelled:
            state.with(replyTarget: .some(nil))
        case .deleteRequested(let id):
            state.with(confirmingDelete: .some(id))
        case .messageRemoved(let id):
            state.with(messages: state.messages.filter { $0.id != id }, replyTarget: .some(state.replyTarget == id ? nil : state.replyTarget))
        case .actionFailed(let message):
            state.with(sendError: .some(message))
        }
    }

    /// Each new message of ours accounts for one waiting send, because identical texts can both be waiting.
    private static func stillWaiting(after incoming: [Message], in state: ThreadState) -> [WaitingMessage] {
        let known = Set(state.messages.map(\.id))
        return incoming.filter { !known.contains($0.id) }.reduce(state.waitingMessages) { remaining, message in
            guard let match = remaining.firstIndex(where: { $0.isReportedBy(message) }) else { return remaining }
            return Array(remaining[..<match] + remaining[(match + 1)...])
        }
    }

    /// Still sending while files remain. The caption and reply went with the first, so a retry won't repeat them.
    private static func afterSending(_ file: OutgoingAttachment, caption: String, from state: ThreadState) -> ThreadState {
        let remaining = state.pendingAttachments.filter { $0 != file }
        return state.with(
            draft: state.draft == caption ? "" : state.draft,
            isSending: !remaining.isEmpty,
            pendingAttachments: remaining,
            replyTarget: .some(nil)
        )
    }

    /// Adds or replaces messages by ID (a resent ID carries new delivery status),
    /// keeping the thread in send order.
    static func merge(_ incoming: [Message], into existing: [Message]) -> [Message] {
        Dictionary((existing + incoming).map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
            .values
            .sorted { ($0.sentAt, $0.id.rawValue) < ($1.sentAt, $1.id.rawValue) }
    }
}
