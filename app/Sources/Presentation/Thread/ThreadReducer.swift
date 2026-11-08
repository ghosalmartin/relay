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
