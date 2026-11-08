public enum PairingReducer: Reducer {
    public static func reduce(_ state: PairingState, _ mutation: PairingMutation) -> PairingState {
        switch mutation {
        case .started: PairingState(step: .preparing, attempt: state.attempt)
        case .stepReached(let step): PairingState(step: step, attempt: state.attempt)
        case .failed(let message): PairingState(step: .failed(message: message), attempt: state.attempt)
        case .retryRequested: PairingState(step: state.step, attempt: state.attempt + 1)
        }
    }
}
