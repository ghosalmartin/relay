public struct PairingState: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        case preparing
        case scanCode(String)
        case confirmEmoji(String)
        case paired
        case failed(message: String)
    }

    public let step: Step
    /// Goes up on each retry, restarting the pairing task.
    public let attempt: Int

    public init(step: Step = .preparing, attempt: Int = 0) {
        self.step = step
        self.attempt = attempt
    }

    /// The instructions shown beside the QR code, in order.
    public static let instructions = [
        "Open Messages on your Android phone",
        "Tap your profile picture, then Device pairing",
        "Tap QR code scanner and point your phone at this screen",
    ]
}

public enum PairingIntent: Equatable, Sendable {
    case retryTapped
}

public enum PairingMutation: Equatable, Sendable {
    case started
    case stepReached(PairingState.Step)
    case failed(String)
    case retryRequested
}
