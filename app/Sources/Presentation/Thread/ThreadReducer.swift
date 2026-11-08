import MessagingDomain

public enum ThreadReducer: Reducer {
    public static func reduce(_ state: ThreadState, _ mutation: ThreadMutation) -> ThreadState {
        switch mutation {
        case .historyLoading:
            state.with(history: .loading)
        case .historyLoaded(let page):
            state.with(messages: merge(page.messages, into: state.messages), olderCursor: .some(page.olderCursor), history: .loaded)
        case .historyFailed(let message):
            state.with(history: .failed(message: message))
        case .olderLoading:
            state.with(isLoadingOlder: true)
        case .olderLoaded(let page):
            state.with(messages: merge(page.messages, into: state.messages), olderCursor: .some(page.olderCursor), isLoadingOlder: false)
        case .olderFailed:
            state.with(isLoadingOlder: false)
        case .messageArrived(let message):
            state.with(messages: merge([message], into: state.messages))
        case .draftChanged(let text):
            state.with(draft: text)
        case .sending:
            state.with(isSending: true, sendError: .some(nil))
        case .sent(let text):
            state.with(draft: state.draft == text ? "" : state.draft, isSending: false)
        case .sendFailed(let message):
            state.with(isSending: false, sendError: .some(message))
        case .sendErrorDismissed:
            state.with(sendError: .some(nil))
        case .conversationChanged(let conversation):
            state.with(conversation: conversation)
        case .attachmentChanged(let id, let content):
            state.with(attachments: state.attachments.merging([id: content]) { _, updated in updated })
        case .fileAdded where state.isSending:
            state     // what's on its way out stays what the user sees until it has gone
        case .fileAdded(let file) where file.data.count > OutgoingAttachment.maximumByteCount:
            state.with(sendError: .some("That file is too big to send. The limit is 100 MB."))
        case .fileAdded(let file):
            state.with(pendingAttachment: .some(file))
        case .fileRemoved where state.isSending:
            state
        case .fileRemoved:
            state.with(pendingAttachment: .some(nil))
        case .fileSent(let caption):
            state.with(draft: state.draft == caption ? "" : state.draft, isSending: false, pendingAttachment: .some(nil))
        }
    }

    /// Adds or replaces messages by ID (a resent ID carries new delivery status),
    /// keeping the thread in send order.
    static func merge(_ incoming: [Message], into existing: [Message]) -> [Message] {
        Dictionary((existing + incoming).map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
            .values
            .sorted { ($0.sentAt, $0.id.rawValue) < ($1.sentAt, $1.id.rawValue) }
    }
}
