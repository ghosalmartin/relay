import Foundation
import MessagingApplication
import MessagingDomain

/// How far along fetching one attachment is.
public enum AttachmentContent: Equatable, Sendable {
    case loading
    case loaded(Data)
    case failed
}

public struct ThreadState: Equatable, Sendable {
    public enum History: Equatable, Sendable {
        case loading
        case loaded
        case failed(message: String)
    }

    public let conversation: Conversation
    public let messages: [Message]
    public let olderCursor: HistoryCursor?
    public let history: History
    public let isLoadingOlder: Bool
    public let draft: String
    public let isSending: Bool
    public let sendError: String?
    /// By attachment ID. Absent until something asks for that attachment.
    public let attachments: [String: AttachmentContent]
    /// The file waiting in the composer to go out with the next send.
    public let pendingAttachment: OutgoingAttachment?

    public init(
        conversation: Conversation,
        messages: [Message] = [],
        olderCursor: HistoryCursor? = nil,
        history: History = .loading,
        isLoadingOlder: Bool = false,
        draft: String = "",
        isSending: Bool = false,
        sendError: String? = nil,
        attachments: [String: AttachmentContent] = [:],
        pendingAttachment: OutgoingAttachment? = nil
    ) {
        self.pendingAttachment = pendingAttachment
        self.conversation = conversation
        self.messages = messages
        self.olderCursor = olderCursor
        self.history = history
        self.isLoadingOlder = isLoadingOlder
        self.draft = draft
        self.isSending = isSending
        self.sendError = sendError
        self.attachments = attachments
    }

    /// A copy with the given fields replaced. For an optional field, `.some(nil)` clears it and omitting it keeps it.
    func with(
        conversation: Conversation? = nil,
        messages: [Message]? = nil,
        olderCursor: HistoryCursor?? = nil,
        history: History? = nil,
        isLoadingOlder: Bool? = nil,
        draft: String? = nil,
        isSending: Bool? = nil,
        sendError: String?? = nil,
        attachments: [String: AttachmentContent]? = nil,
        pendingAttachment: OutgoingAttachment?? = nil
    ) -> ThreadState {
        ThreadState(
            conversation: conversation ?? self.conversation,
            messages: messages ?? self.messages,
            olderCursor: olderCursor ?? self.olderCursor,
            history: history ?? self.history,
            isLoadingOlder: isLoadingOlder ?? self.isLoadingOlder,
            draft: draft ?? self.draft,
            isSending: isSending ?? self.isSending,
            sendError: sendError ?? self.sendError,
            attachments: attachments ?? self.attachments,
            pendingAttachment: pendingAttachment ?? self.pendingAttachment
        )
    }

    public var title: String { conversation.title }
    public var canSend: Bool { !isSending && (pendingAttachment != nil || SendText.sendableText(from: draft) != nil) }
    public var pendingAttachmentSize: String? {
        pendingAttachment.map { ByteCountFormatter.string(fromByteCount: Int64($0.data.count), countStyle: .file) }
    }
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
    case conversationChanged(Conversation)
    /// A picture scrolled into view and needs its contents.
    case attachmentAppeared(Attachment)
    case attachmentTapped(Attachment)
    /// A file was picked, dropped or pasted. Nil if it couldn't be read.
    case fileRead(OutgoingAttachment?)
    case fileRemoved
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
    /// Carries the text that went out, because the draft may have moved on while it was sending.
    case sent(String)
    case sendFailed(String)
    case sendErrorDismissed
    case conversationChanged(Conversation)
    case attachmentChanged(id: String, AttachmentContent)
    case fileAdded(OutgoingAttachment)
    case fileRemoved
    /// Carries the caption that went out, because the draft may have moved on while it was sending.
    case fileSent(caption: String)
}
