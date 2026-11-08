public enum PairingReducer: Reducer {
    public static func reduce(_ state: PairingState, _ mutation: PairingMutation) -> PairingState {
        switch mutation {
        case .started: PairingState(step: .preparing)
        case .stepReached(let step): PairingState(step: step)
        case .failed(let message): PairingState(step: .failed(message: message))
        }
    }
}
