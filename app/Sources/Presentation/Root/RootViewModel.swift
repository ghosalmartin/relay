import MessagingApplication
import MessagingDomain
import Observation

/// Decides between pairing and the inbox, and keeps credentials saved for the app's lifetime.
@MainActor @Observable
public final class RootViewModel {
    public private(set) var state: RootState = .launching

    private let startSession: StartSession
    private let persistSessionChanges: PersistSessionChanges
    private let observeConnectionStatus: ObserveConnectionStatus
    private let unpair: Unpair
    private let phoneWaker: any PhoneWaker

    public init(
        startSession: StartSession,
        persistSessionChanges: PersistSessionChanges,
        observeConnectionStatus: ObserveConnectionStatus,
        unpair: Unpair,
        phoneWaker: any PhoneWaker
    ) {
        self.startSession = startSession
        self.persistSessionChanges = persistSessionChanges
        self.observeConnectionStatus = observeConnectionStatus
        self.unpair = unpair
        self.phoneWaker = phoneWaker
    }

    /// Runs for as long as the window is open. Call from the view's `.task`.
    public func run() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.persistSessionChanges() }
            group.addTask { await self.followConnection() }
            group.addTask { await self.launch() }
        }
    }

    @discardableResult
    public func send(_ intent: RootIntent) -> Task<Void, Never> {
        switch intent {
        case .pairingFinished:
            apply(.paired)
            offerPhoneWakeSetup()
            return Task {}
        case .retryTapped:
            apply(.retrying)
            return Task { await launch() }
        case .signOutTapped:
            return Task { await signOut() }
        case .phoneWakeSetupCompleted:
            phoneWaker.markSetUp()
            apply(.phoneWakeSetupEnded)
            return Task {}
        case .phoneWakeSetupSkipped:
            apply(.phoneWakeSetupEnded)
            return Task {}
        }
    }

    private func launch() async {
        do {
            apply(.sessionStarted(try await startSession()))
            offerPhoneWakeSetup()
        } catch {
            apply(.sessionFailed(String(describing: error)))
        }
    }

    /// Asked again next launch if skipped, because without it a stalled phone stays stalled.
    private func offerPhoneWakeSetup() {
        if !phoneWaker.isSetUp { apply(.phoneWakeSetupNeeded) }
    }

    private func followConnection() async {
        for await status in observeConnectionStatus() {
            apply(.connectionChanged(status))
        }
    }

    private func signOut() async {
        try? await unpair()  // even if the phone can't be told, forget this device locally
        apply(.signedOut)
    }

    private func apply(_ mutation: RootMutation) {
        state = RootReducer.reduce(state, mutation)
    }
}
