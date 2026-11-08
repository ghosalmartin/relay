import MessagingDomain

public enum ThreadReducer: Reducer {
    public static func reduce(_ state: ThreadState, _ mutation: ThreadMutation) -> ThreadState {
        var next = state
        switch mutation {
        case .historyLoading:
            next.history = .loading
        case .historyLoaded(let page):
            next.messages = merge(page.messages, into: state.messages)
            next.olderCursor = page.olderCursor
            next.history = .loaded
        case .historyFailed(let message):
            next.history = .failed(message: message)
        case .olderLoading:
            next.isLoadingOlder = true
        case .olderLoaded(let page):
            next.messages = merge(page.messages, into: state.messages)
            next.olderCursor = page.olderCursor
            next.isLoadingOlder = false
        case .olderFailed:
            next.isLoadingOlder = false
        case .messageArrived(let message):
            next.messages = merge([message], into: state.messages)
        case .draftChanged(let text):
            next.draft = text
        case .sending:
            next.isSending = true
            next.sendError = nil
        case .sent:
            next.isSending = false
            next.draft = ""
        case .sendFailed(let message):
            next.isSending = false
            next.sendError = message
        case .sendErrorDismissed:
            next.sendError = nil
        }
        return next
    }

    /// Adds or replaces messages by ID (a resent ID carries new delivery status),
    /// keeping the thread in send order.
    static func merge(_ incoming: [Message], into existing: [Message]) -> [Message] {
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        for message in incoming {
            byID[message.id] = message
        }
        return byID.values.sorted { ($0.sentAt, $0.id.rawValue) < ($1.sentAt, $1.id.rawValue) }
    }
}
