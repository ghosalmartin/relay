import MessagingApplication
import MessagingDomain
import Observation

@MainActor @Observable
public final class PairingViewModel {
    public private(set) var state = PairingState()

    private let pairDevice: PairDevice
    private let scriptedSignIn: AccountCookies?
    private let cookiePaste: CookiePaste
    private let onPaired: @MainActor () -> Void

    /// - Parameters:
    ///   - scriptedSignIn: skips the web sign-in by pairing with these, for UI tests.
    ///   - onPaired: called once the phone accepts this device.
    public init(
        pairDevice: PairDevice,
        scriptedSignIn: AccountCookies? = nil,
        cookiePaste: CookiePaste = .unavailable,
        onPaired: @escaping @MainActor () -> Void
    ) {
        self.pairDevice = pairDevice
        self.scriptedSignIn = scriptedSignIn
        self.cookiePaste = cookiePaste
        self.onPaired = onPaired
    }

    /// Whether the view should show the Google sign-in page.
    public var showsWebSignIn: Bool { scriptedSignIn == nil }

    /// Changes whenever pairing should start over; drive the view's `.task(id:)` with it.
    public var runID: Int { state.attempt }

    /// Call from the view's `.task(id: runID)`.
    public func run() async {
        if let scriptedSignIn { await pair(using: scriptedSignIn) }
    }

    @discardableResult
    public func send(_ intent: PairingIntent) -> Task<Void, Never> {
        switch intent {
        case .signedIn(let cookies):
            return Task { await pair(using: cookies) }
        case .pasteTapped:
            guard let cookies = cookiePaste.read().flatMap(cookiePaste.parse) else {
                apply(.pasteRejected)     // not our data, so the clipboard is left alone
                return Task {}
            }
            cookiePaste.clear()
            return Task { await pair(using: cookies) }
        case .signInMethodChosen(let method):
            apply(.signInMethodChosen(method))
            return Task {}
        case .retryTapped:
            apply(.retryRequested)
            return Task {}
        }
    }

    private func pair(using cookies: AccountCookies) async {
        guard state.step == .signIn else { return }     // the sign-in page can report more than once
        apply(.started)
        do {
            for try await step in pairDevice(with: cookies) {
                apply(.stepReached(Self.step(for: step)))
            }
            if state.step == .paired { onPaired() }
        } catch is CancellationError {
            return
        } catch {
            apply(.failed(Self.describe(error)))
        }
    }

    private func apply(_ mutation: PairingMutation) {
        state = PairingReducer.reduce(state, mutation)
    }

    private static func step(for step: PairingStep) -> PairingState.Step {
        switch step {
        case .confirmEmoji(let emoji): .confirmEmoji(emoji)
        case .paired: .paired
        }
    }

    static func describe(_ error: any Error) -> String {
        switch error {
        case MessagingError.phoneUnreachable: "Your phone isn't responding. Check it's on and connected."
        case MessagingError.phoneMissedPairing:
            "Your phone didn't answer. Open Messages on your phone, check Device pairing is on for this Google account, keep the app open, and try again."
        case MessagingError.backend(let message): message
        default: "Something went wrong."
        }
    }
}
