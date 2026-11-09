public enum NewConversationReducer: Reducer {
    public static func reduce(_ state: NewConversationState, _ mutation: NewConversationMutation) -> NewConversationState {
        switch mutation {
        case .contactsLoading:
            state.with(contacts: .loading)
        case .contactsLoaded(let contacts):
            state.with(contacts: .loaded(contacts))
        case .contactsFailed(let message):
            state.with(contacts: .failed(message: message))
        case .queryChanged(let text):
            state.with(query: text)
        case .starting:
            state.with(isStarting: true, startError: .some(nil))
        case .started:
            state.with(isStarting: false, isFinished: true)
        case .startFailed(let message):
            state.with(isStarting: false, startError: .some(message))
        case .errorDismissed:
            state.with(startError: .some(nil))
        }
    }
}
