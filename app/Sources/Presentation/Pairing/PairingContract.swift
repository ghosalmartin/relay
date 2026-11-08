public struct PairingState: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        case preparing
        case scanCode(String)
        case confirmEmoji(String)
        case paired
        case failed(message: String)
    }

    public var step: Step = .preparing

    public init(step: Step = .preparing) { self.step = step }

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
}
