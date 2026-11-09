import MessagingDomain

/// What the pairing screen should show next.
public enum PairingStep: Equatable, Sendable {
    case confirmEmoji(String)
    case paired
}

/// Pairs with the phone using a signed-in account, and finishes once the phone has accepted this device.
public struct PairDevice: Sendable {
    private let client: any MessagingClient

    /// Each try wakes the phone a little more, but the user is left waiting through every one.
    static let attempts = 3

    public init(client: any MessagingClient) {
        self.client = client
    }

    public func callAsFunction(with cookies: AccountCookies) -> AsyncThrowingStream<PairingStep, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(with: cookies, reportingTo: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        with cookies: AccountCookies,
        reportingTo output: AsyncThrowingStream<PairingStep, any Error>.Continuation
    ) async throws {
        for attemptsLeft in (0..<Self.attempts).reversed() {
            do {
                return try await attempt(with: cookies, reportingTo: output)
            } catch MessagingError.phoneMissedPairing where attemptsLeft > 0 {
                continue
            }
        }
    }

    private func attempt(
        with cookies: AccountCookies,
        reportingTo output: AsyncThrowingStream<PairingStep, any Error>.Continuation
    ) async throws {
        let events = client.events()          // subscribe before starting, so the emoji can't be missed
        try await withThrowingTaskGroup(of: Void.self) { group in
            // startPairing only returns once the phone has answered, so the steps are followed alongside it.
            group.addTask { try await client.startPairing(with: cookies) }
            group.addTask { await report(events, to: output) }
            while try await group.next() != nil {}   // the first failure ends pairing
        }
    }

    private func report(
        _ events: AsyncStream<MessagingEvent>,
        to output: AsyncThrowingStream<PairingStep, any Error>.Continuation
    ) async {
        for await event in events {
            guard let step = Self.step(for: event) else { continue }
            output.yield(step)
            if step == .paired { return }
        }
    }

    static func step(for event: MessagingEvent) -> PairingStep? {
        switch event {
        case .pairingConfirmationEmoji(let emoji): .confirmEmoji(emoji)
        case .paired: .paired
        default: nil
        }
    }
}
