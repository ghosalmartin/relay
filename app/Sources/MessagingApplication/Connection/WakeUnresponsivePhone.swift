import MessagingDomain

/// Wakes a phone that has stopped answering, then stops as soon as it responds.
///
/// Every attempt is followed by a wait, so a phone that keeps stalling can't cause a run of them, and
/// one that is simply off isn't bothered all night. Start it once at launch, in a task that lives as long as the app.
public struct WakeUnresponsivePhone: Sendable {
    /// Long enough for the phone to respond, which has taken up to 25 seconds, and short enough to finish
    /// before `RecoverUnresponsivePhone` replaces the connection.
    public static let attemptLength: Duration = .seconds(45)
    public static let waits: [Duration] = [.seconds(60), .seconds(300), .seconds(900), .seconds(1800)]

    private let needsWaking: LiveValue<Bool>
    private let waker: any PhoneWaker
    private let clock: any Clock<Duration>

    public init(needsWaking: LiveValue<Bool>, waker: any PhoneWaker, clock: any Clock<Duration> = ContinuousClock()) {
        self.needsWaking = needsWaking
        self.waker = waker
        self.clock = clock
    }

    public func callAsFunction() async {
        for await isNeeded in needsWaking.values() where isNeeded {
            await wakeUntilThePhoneAnswers()
        }
    }

    private func wakeUntilThePhoneAnswers() async {
        let last = Self.waits.count - 1
        for attempt in sequence(first: 0, next: { min($0 + 1, last) }) {
            guard needsWaking.value, waker.isSetUp else { return }
            await waker.startWaking()
            await waitForAnswer()
            await waker.stopWaking()
            do {
                try await clock.sleep(for: Self.waits[attempt])
            } catch {
                return     // cancelled: the app is going away
            }
        }
    }

    private func waitForAnswer() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [clock] in try? await clock.sleep(for: Self.attemptLength) }
            group.addTask { [needsWaking] in
                for await isNeeded in needsWaking.values() where !isNeeded { return }
            }
            await group.next()
            group.cancelAll()
        }
    }
}
