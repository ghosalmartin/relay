import Foundation
import MessagingApplication
import MessagingDomain

public struct InboxState: Equatable, Sendable {
    public let conversations: [Conversation]
    public let isSyncing: Bool
    public let connection: ConnectionStatus
    public let selection: ConversationID?
    /// A conversation asked for from an alert that hasn't synced yet.
    public let pendingOpen: ConversationID?
    public let searchText: String
    public let avatars: [ParticipantID: Data]
    /// Already asked for, including people who turned out to have no photo, so nobody is asked for twice.
    public let requestedAvatars: Set<ParticipantID>
    /// Whether the new conversation sheet is up.
    public let isComposing: Bool
    /// The conversation waiting on "are you sure?".
    public let confirmingDelete: ConversationID?
    public let actionError: String?

    public init(
        conversations: [Conversation] = [],
        isSyncing: Bool = true,
        connection: ConnectionStatus = .connecting,
        selection: ConversationID? = nil,
        pendingOpen: ConversationID? = nil,
        searchText: String = "",
        avatars: [ParticipantID: Data] = [:],
        requestedAvatars: Set<ParticipantID> = [],
        isComposing: Bool = false,
        confirmingDelete: ConversationID? = nil,
        actionError: String? = nil
    ) {
        self.confirmingDelete = confirmingDelete
        self.actionError = actionError
        self.isComposing = isComposing
        self.avatars = avatars
        self.requestedAvatars = requestedAvatars
        self.conversations = conversations
        self.isSyncing = isSyncing
        self.connection = connection
        self.selection = selection
        self.pendingOpen = pendingOpen
        self.searchText = searchText
    }

    /// A copy with the given fields replaced. For an optional field, `.some(nil)` clears it and omitting it keeps it.
    func with(
        conversations: [Conversation]? = nil,
        isSyncing: Bool? = nil,
        connection: ConnectionStatus? = nil,
        selection: ConversationID?? = nil,
        pendingOpen: ConversationID?? = nil,
        searchText: String? = nil,
        avatars: [ParticipantID: Data]? = nil,
        requestedAvatars: Set<ParticipantID>? = nil,
        isComposing: Bool? = nil,
        confirmingDelete: ConversationID?? = nil,
        actionError: String?? = nil
    ) -> InboxState {
        InboxState(
            conversations: conversations ?? self.conversations,
            isSyncing: isSyncing ?? self.isSyncing,
            connection: connection ?? self.connection,
            selection: selection ?? self.selection,
            pendingOpen: pendingOpen ?? self.pendingOpen,
            searchText: searchText ?? self.searchText,
            avatars: avatars ?? self.avatars,
            requestedAvatars: requestedAvatars ?? self.requestedAvatars,
            isComposing: isComposing ?? self.isComposing,
            confirmingDelete: confirmingDelete ?? self.confirmingDelete,
            actionError: actionError ?? self.actionError
        )
    }

    /// The rows to show: conversations matching the search, newest first.
    public var rows: [ConversationRow] {
        conversations.filter(matchesSearch).map { conversation in
            ConversationRow(conversation, photos: conversation.avatarParticipants.compactMap { avatars[$0] })
        }
    }

    /// Waits for the sync to finish, so the phone gets one request for the whole inbox
    /// rather than one for each conversation as it streams in.
    public var avatarsToLoad: Set<ParticipantID> {
        guard !isSyncing else { return [] }
        return Set(conversations.flatMap(\.avatarParticipants)).subtracting(requestedAvatars)
    }

    /// The banner to show above the list, if any.
    public var banner: ConnectionBanner? { ConnectionBanner(connection) }

    /// Whether to show "No conversations" (as opposed to a spinner or a list).
    public var isEmpty: Bool { !isSyncing && conversations.isEmpty }

    /// The conversation ⌘ and a digit goes to: its place in the list as shown.
    public func conversationID(atShortcut position: Int) -> ConversationID? {
        let visible = rows
        return visible.indices.contains(position - 1) ? visible[position - 1].id : nil
    }

    public var selectedConversation: Conversation? {
        conversations.first { $0.id == selection }
    }

    private func matchesSearch(_ conversation: Conversation) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return conversation.title.localizedCaseInsensitiveContains(query)
            || (conversation.preview?.text.localizedCaseInsensitiveContains(query) ?? false)
    }
}

/// One line in the sidebar, already worded for display.
public struct ConversationRow: Identifiable, Equatable, Sendable {
    public let id: ConversationID
    public let title: String
    public let preview: String
    public let lastActivity: Date
    public let isUnread: Bool
    public let initials: String
    public let avatar: Data?
    /// A second face, for a group.
    public let secondAvatar: Data?

    init(_ conversation: Conversation, photos: [Data] = []) {
        avatar = photos.first
        secondAvatar = photos.dropFirst().first
        id = conversation.id
        title = conversation.title
        preview = Self.previewText(conversation.preview)
        lastActivity = conversation.lastActivity
        isUnread = conversation.isUnread
        initials = Self.initials(of: conversation.title)
    }

    static func previewText(_ preview: MessagePreview?) -> String {
        guard let preview else { return "" }
        if preview.isFromMe { return "You: \(preview.text)" }
        if let sender = preview.senderName { return "\(sender): \(preview.text)" }
        return preview.text
    }

    /// Up to two initials for the avatar; digits and symbols give "#".
    static func initials(of title: String) -> String {
        let letters = title.split(separator: " ").compactMap(\.first).filter(\.isLetter)
        return letters.isEmpty ? "#" : String(letters.prefix(2)).uppercased()
    }
}

/// A status strip shown above the conversation list while the phone link isn't healthy.
public enum ConnectionBanner: Equatable, Sendable {
    case connecting
    case phoneUnreachable
    case reconnecting

    init?(_ status: ConnectionStatus) {
        switch status {
        case .connecting: self = .connecting
        case .phoneUnreachable: self = .phoneUnreachable
        case .reconnecting: self = .reconnecting
        case .online, .lost, .loggedOut: return nil
        }
    }

    public var message: String {
        switch self {
        case .connecting: "Connecting to your phone…"
        case .phoneUnreachable: "Your phone isn't responding. Check it's on and connected."
        case .reconnecting: "Reconnecting…"
        }
    }
}

public enum InboxIntent: Equatable, Sendable {
    case selected(ConversationID?)
    case searchChanged(String)
    case shortcutPressed(Int)
    case composeTapped
    case composeDismissed
    case archiveTapped(ConversationID)
    case muteTapped(ConversationID, isMuted: Bool)
    case deleteTapped(ConversationID)
    case deleteConfirmed
    case deleteCancelled
    case actionErrorDismissed
}

public enum InboxMutation: Equatable, Sendable {
    case inboxChanged(InboxSnapshot)
    case connectionChanged(ConnectionStatus)
    case selected(ConversationID?)
    case openRequested(ConversationID)
    case searchChanged(String)
    case avatarsRequested(Set<ParticipantID>)
    case avatarsLoaded([ParticipantID: Data])
    case avatarsFailed(Set<ParticipantID>)
    case composingChanged(Bool)
    case deleteRequested(ConversationID?)
    case actionFailed(String?)
}
