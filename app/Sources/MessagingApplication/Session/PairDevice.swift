import MessagingDomain

/// What the pairing screen should show next.
public enum PairingStep: Equatable, Sendable {
    case scanCode(String)
    case confirmEmoji(String)
    case paired
}

/// Runs QR pairing: shows a code, swaps it for a fresh one before it expires,
/// and finishes once the phone has accepted this device.
public struct PairDevice: Sendable {
    /// Codes expire after about 30 seconds; refresh a little early.
    public static let codeLifetime: Duration = .seconds(25)

    private let client: any MessagingClient
    private let clock: any Clock<Duration>

    public init(client: any MessagingClient, clock: any Clock<Duration> = ContinuousClock()) {
        self.client = client
        self.clock = clock
    }

    public func callAsFunction() -> AsyncThrowingStream<PairingStep, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(reportingTo: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(reportingTo output: AsyncThrowingStream<PairingStep, any Error>.Continuation) async throws {
        let events = client.events()          // subscribe before starting, so no code is missed
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await refreshCodes() }
            try await client.startPairing()
            for await event in events {
                guard let step = Self.step(for: event) else { continue }
                output.yield(step)
                if step == .paired { break }
            }
            group.cancelAll()
        }
    }

    private func refreshCodes() async throws {
        while true {
            try await clock.sleep(for: Self.codeLifetime)
            try await client.refreshPairingCode()
        }
    }

    static func step(for event: MessagingEvent) -> PairingStep? {
        switch event {
        case .pairingCode(let code): .scanCode(code)
        case .pairingConfirmationEmoji(let emoji): .confirmEmoji(emoji)
        case .paired: .paired
        default: nil
        }
    }
}
