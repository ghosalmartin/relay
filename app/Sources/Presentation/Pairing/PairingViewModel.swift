import MessagingApplication
import Observation

@MainActor @Observable
public final class PairingViewModel {
    public private(set) var state = PairingState()

    private let pairDevice: PairDevice
    private let onPaired: @MainActor () -> Void

    /// - Parameter onPaired: called once the phone accepts this device.
    public init(pairDevice: PairDevice, onPaired: @escaping @MainActor () -> Void) {
        self.pairDevice = pairDevice
        self.onPaired = onPaired
    }

    /// Runs pairing until it succeeds, fails, or the view goes away. Call from `.task(id: attempt)`.
    public func run() async {
        apply(.started)
        do {
            for try await step in pairDevice() {
                apply(.stepReached(Self.step(for: step)))
            }
            if state.step == .paired { onPaired() }
        } catch is CancellationError {
            return
        } catch {
            apply(.failed(String(describing: error)))
        }
    }

    /// Changes whenever pairing should start over; drive the view's `.task(id:)` with it.
    public var runID: Int { state.attempt }

    public func send(_ intent: PairingIntent) {
        switch intent {
        case .retryTapped: apply(.retryRequested)
        }
    }

    private func apply(_ mutation: PairingMutation) {
        state = PairingReducer.reduce(state, mutation)
    }

    private static func step(for step: PairingStep) -> PairingState.Step {
        switch step {
        case .scanCode(let code): .scanCode(code)
        case .confirmEmoji(let emoji): .confirmEmoji(emoji)
        case .paired: .paired
        }
    }
}
