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
            pendingOpen: .some(arrived == nil ? state.pendingOpen : nil)
        )
    }

    private static func contains(_ id: ConversationID, _ conversations: [Conversation]) -> Bool {
        conversations.contains { $0.id == id }
    }
}
