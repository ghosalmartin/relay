import MessagingDomain

public enum InboxReducer: Reducer {
    public static func reduce(_ state: InboxState, _ mutation: InboxMutation) -> InboxState {
        var next = state
        switch mutation {
        case .inboxChanged(let snapshot):
            next.conversations = snapshot.conversations
            next.isSyncing = snapshot.isSyncing
            next.selection = keepSelection(state.selection, in: next)
        case .connectionChanged(let status):
            next.connection = status
        case .selected(let id):
            next.selection = id
        case .searchChanged(let text):
            next.searchText = text
        }
        return next
    }

    /// Drop the selection if its conversation has gone (deleted on the phone, or logged out).
    private static func keepSelection(_ selection: ConversationID?, in state: InboxState) -> ConversationID? {
        guard let selection, state.conversations.contains(where: { $0.id == selection }) else { return nil }
        return selection
    }
}
