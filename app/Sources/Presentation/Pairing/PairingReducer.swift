public enum PairingReducer: Reducer {
    public static let unusablePaste = "That didn't include your sign-in. Copy the request called config as cURL, then paste again."

    public static func reduce(_ state: PairingState, _ mutation: PairingMutation) -> PairingState {
        switch mutation {
        case .started: moved(state, to: .preparing)
        case .stepReached(let step): moved(state, to: step)
        case .failed(let message): moved(state, to: .failed(message: message))
        case .retryRequested:
            PairingState(step: .signIn, attempt: state.attempt + 1, signInMethod: state.signInMethod)
        case .signInMethodChosen(let method):
            PairingState(step: state.step, attempt: state.attempt, signInMethod: method)
        case .pasteRejected:
            PairingState(step: state.step, attempt: state.attempt, signInMethod: state.signInMethod, pasteProblem: unusablePaste)
        }
    }

    private static func moved(_ state: PairingState, to step: PairingState.Step) -> PairingState {
        PairingState(step: step, attempt: state.attempt, signInMethod: state.signInMethod)
    }
}
