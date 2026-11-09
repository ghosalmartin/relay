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
    /// The files waiting in the composer to go out with the next send.
    public let pendingAttachments: [OutgoingAttachment]
    /// Assumed fine until told otherwise, so opening a chat doesn't count as the phone coming back.
    public let connection: ConnectionStatus
    /// The message the next send answers.
    public let replyTarget: MessageID?
    /// The message waiting on "are you sure?".
    public let confirmingDelete: MessageID?
    /// Sends the phone hasn't answered yet. They can still go out, so they must not look failed.
    public let waitingMessages: [WaitingMessage]

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
        pendingAttachments: [OutgoingAttachment] = [],
        connection: ConnectionStatus = .online,
        replyTarget: MessageID? = nil,
        confirmingDelete: MessageID? = nil,
        waitingMessages: [WaitingMessage] = []
    ) {
        self.waitingMessages = waitingMessages
        self.connection = connection
        self.replyTarget = replyTarget
        self.confirmingDelete = confirmingDelete
        self.pendingAttachments = pendingAttachments
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
        pendingAttachments: [OutgoingAttachment]? = nil,
        connection: ConnectionStatus? = nil,
        replyTarget: MessageID?? = nil,
        confirmingDelete: MessageID?? = nil,
        waitingMessages: [WaitingMessage]? = nil
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
            pendingAttachments: pendingAttachments ?? self.pendingAttachments,
            connection: connection ?? self.connection,
            replyTarget: replyTarget ?? self.replyTarget,
            confirmingDelete: confirmingDelete ?? self.confirmingDelete,
            waitingMessages: waitingMessages ?? self.waitingMessages
        )
    }

    public var title: String { conversation.title }
    public var waitingNotice: String? {
        switch waitingMessages.count {
        case 0: nil
        case 1: "Waiting for your phone. This message should go out when it responds, so don't send it again."
        case let count: "Waiting for your phone. These \(count) messages should go out when it responds, so don't send them again."
        }
    }
    public static let quickReactions = ["👍", "❤️", "😂", "😮", "😢", "👎"]
    public var replyPreview: String? {
        guard let replyTarget else { return nil }
        let text = messages.first { $0.id == replyTarget }?.text ?? ""
        return text.isEmpty ? "Attachment" : text
    }
    func isPhoneReturn(to status: ConnectionStatus) -> Bool { status == .online && connection != .online }
    public static let maximumPendingFiles = 10
    public var canSend: Bool { !isSending && (!pendingAttachments.isEmpty || SendText.sendableText(from: draft) != nil) }
    public var pendingFiles: [PendingFile] {
        pendingAttachments.map { PendingFile(attachment: $0, sizeText: ByteCountFormatter.string(fromByteCount: Int64($0.data.count), countStyle: .file)) }
    }
    public var canLoadOlder: Bool { olderCursor != nil && !isLoadingOlder }
    public var newestIncomingMessage: Message? { messages.last { !$0.isFromMe } }

    /// What the thread view draws, top to bottom.
    public func items(calendar: Calendar = .current) -> [ThreadItem] {
        ThreadLayout.items(for: messages, in: conversation, calendar: calendar)
    }
}

/// A file in the composer, already worded for display.
public struct PendingFile: Identifiable, Equatable, Sendable {
    public let attachment: OutgoingAttachment
    public let sizeText: String

    public var id: OutgoingAttachment { attachment }
}

/// A send the phone hasn't answered, described well enough to recognise when the phone reports it.
public struct WaitingMessage: Equatable, Sendable {
    public let text: String
    public let hasFile: Bool

    public init(text: String, hasFile: Bool) {
        self.text = text
        self.hasFile = hasFile
    }

    func isReportedBy(_ message: Message) -> Bool {
        let carriesFile = message.parts.contains { $0.text == nil }
        return message.isFromMe && message.text == text && carriesFile == hasFile
    }
}

public enum ThreadIntent: Equatable, Sendable {
    case draftChanged(String)
    case sendTapped
    case loadOlderTapped
    case retryHistoryTapped
    case sendErrorDismissed
    case waitingDismissed
    case conversationChanged(Conversation)
    /// A picture scrolled into view and needs its contents.
    case attachmentAppeared(Attachment)
    case attachmentTapped(Attachment)
    /// For when a clip won't play in the bubble.
    case attachmentOpenTapped(Attachment)
    /// A file was picked, dropped or pasted. Nil if it couldn't be read.
    case fileRead(OutgoingAttachment?)
    case fileRemoved(OutgoingAttachment)
    case replyTapped(MessageID)
    case replyCancelled
    case reactionChosen(String, MessageID)
    case deleteTapped(MessageID)
    case deleteConfirmed
    case deleteCancelled
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
    case waitingDismissed
    /// The phone didn't answer in time, but has the request. Carries what the composer held, and the file if it was one.
    case waitingForPhone(WaitingMessage, typed: String, file: OutgoingAttachment?)
    case conversationChanged(Conversation)
    case attachmentChanged(id: String, AttachmentContent)
    case fileAdded(OutgoingAttachment)
    case fileRemoved(OutgoingAttachment)
    /// Carries the caption that went out, because the draft may have moved on while it was sending.
    case fileSent(OutgoingAttachment, caption: String)
    case connectionChanged(ConnectionStatus)
    /// A refresh of the newest page, which leaves the place in older history alone.
    case caughtUp(MessagePage)
    case replyStarted(MessageID)
    case replyCancelled
    case deleteRequested(MessageID?)
    case messageRemoved(MessageID)
    /// Something other than a send failed, so no send has stopped.
    case actionFailed(String)
}
