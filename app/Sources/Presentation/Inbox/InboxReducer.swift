import MessagingApplication
import MessagingDomain

public enum InboxReducer: Reducer {
    public static func reduce(_ state: InboxState, _ mutation: InboxMutation) -> InboxState {
        switch mutation {
        case .inboxChanged(let snapshot):
            afterSync(of: snapshot, from: state)
        case .connectionChanged(let status):
            state.with(connection: status)
        case .selected(let id):
            state.with(selection: .some(id), pendingOpen: .some(nil))
        case .openRequested(let id) where contains(id, state.conversations):
            state.with(selection: .some(id), pendingOpen: .some(nil))
        case .openRequested(let id):
            state.with(pendingOpen: .some(id))
        case .searchChanged(let text):
            state.with(searchText: text)
        case .avatarsRequested(let ids):
            state.with(requestedAvatars: state.requestedAvatars.union(ids))
        case .avatarsLoaded(let photos):
            state.with(avatars: state.avatars.merging(photos) { _, new in new })
        case .avatarsFailed(let ids):
            state.with(requestedAvatars: state.requestedAvatars.subtracting(ids))     // the next inbox change tries again
        case .composingChanged(let isComposing):
            state.with(isComposing: isComposing)
        case .deleteRequested(let id):
            state.with(confirmingDelete: .some(id))
        case .actionFailed(let message):
            state.with(actionError: .some(message))
        }
    }

    /// A waiting conversation is opened once it arrives. The selection is dropped if its
    /// conversation has gone (deleted on the phone, or logged out).
    private static func afterSync(of snapshot: InboxSnapshot, from state: InboxState) -> InboxState {
        let arrived = state.pendingOpen.flatMap { contains($0, snapshot.conversations) ? $0 : nil }
        let selection = (arrived ?? state.selection).flatMap { contains($0, snapshot.conversations) ? $0 : nil }
        return state.with(
            conversations: snapshot.conversations,
            isSyncing: snapshot.isSyncing,
            selection: .some(selection),
            pendingOpen: .some(arrived == nil ? state.pendingOpen : nil),
            // An empty inbox means signed out, and the next account shouldn't see these photos.
            avatars: snapshot.conversations.isEmpty ? [:] : state.avatars,
            requestedAvatars: snapshot.conversations.isEmpty ? [] : state.requestedAvatars
        )
    }

    private static func contains(_ id: ConversationID, _ conversations: [Conversation]) -> Bool {
        conversations.contains { $0.id == id }
    }
}
