import MessagingDomain

/// Does automatically what restarting the app does when the phone goes quiet: builds a fresh
/// connection from the saved login. A new connection can get an answer where the old one won't.
///
/// Waits longer between attempts, because a phone that is simply off shouldn't be retried
/// flat out all night. Start it once at launch, in a task that lives as long as the app.
public struct RecoverUnresponsivePhone: Sendable {
    public static let waits: [Duration] = [.seconds(60), .seconds(120), .seconds(300), .seconds(900)]

    private let connection: LiveValue<ConnectionStatus>
    private let startSession: StartSession
    private let clock: any Clock<Duration>

    public init(connection: LiveValue<ConnectionStatus>, startSession: StartSession, clock: any Clock<Duration> = ContinuousClock()) {
        self.connection = connection
        self.startSession = startSession
        self.clock = clock
    }

    public func callAsFunction() async {
        for await status in connection.values() where status == .phoneUnreachable {
            await reconnectUntilThePhoneAnswers()
        }
    }

    private func reconnectUntilThePhoneAnswers() async {
        let last = Self.waits.count - 1
        for attempt in sequence(first: 0, next: { min($0 + 1, last) }) {
            do {
                try await clock.sleep(for: Self.waits[attempt])
            } catch {
                return     // cancelled: the app is going away
            }
            guard connection.value == .phoneUnreachable else { return }
            // A failed attempt just waits for the next one; only a missing login ends the retries.
            if (try? await startSession()) == .needsPairing { return }
        }
    }
}
