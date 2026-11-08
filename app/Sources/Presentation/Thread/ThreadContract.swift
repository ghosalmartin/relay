import Foundation
import MessagingApplication
import MessagingDomain

public struct ThreadState: Equatable, Sendable {
    public enum History: Equatable, Sendable {
        case loading
        case loaded
        case failed(message: String)
    }

    public let conversation: Conversation
    public var messages: [Message] = []
    public var olderCursor: HistoryCursor?
    public var history: History = .loading
    public var isLoadingOlder = false
    public var draft = ""
    public var isSending = false
    public var sendError: String?

    public init(conversation: Conversation) {
        self.conversation = conversation
    }

    public var title: String { conversation.title }
    public var canSend: Bool { !isSending && SendText.sendableText(from: draft) != nil }
    public var canLoadOlder: Bool { olderCursor != nil && !isLoadingOlder }
    public var newestIncomingMessage: Message? { messages.last { !$0.isFromMe } }

    /// What the thread view draws, top to bottom.
    public func items(calendar: Calendar = .current) -> [ThreadItem] {
        ThreadLayout.items(for: messages, in: conversation, calendar: calendar)
    }
}

public enum ThreadIntent: Equatable, Sendable {
    case draftChanged(String)
    case sendTapped
    case loadOlderTapped
    case retryHistoryTapped
    case sendErrorDismissed
}

public enum ThreadMutation: Equatable, Sendable {
    case historyLoading
    case historyLoaded(MessagePage)
    case historyFailed(String)
    case olderLoading
    case olderLoaded(MessagePage)
    case olderFailed
    case messageArrived(Message)
    case draftChanged(String)
    case sending
    case sent
    case sendFailed(String)
    case sendErrorDismissed
}
