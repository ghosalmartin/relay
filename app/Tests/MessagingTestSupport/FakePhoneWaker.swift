import MessagingDomain
import Synchronization

/// Records what was asked of it. Set up by default, so screens under test go straight to the inbox.
public final class FakePhoneWaker: PhoneWaker {
    public enum Call: Equatable, Sendable {
        case startWaking
        case stopWaking
        case forget
    }

    private struct State {
        var isSetUp: Bool
        var calls: [Call] = []
    }

    private let state: Mutex<State>

    public init(isSetUp: Bool = true) {
        state = Mutex(State(isSetUp: isSetUp))
    }

    public var isSetUp: Bool { state.withLock { $0.isSetUp } }
    public var calls: [Call] { state.withLock { $0.calls } }

    public func markSetUp() {
        state.withLock { $0.isSetUp = true }
    }

    public func startWaking() async {
        state.withLock { $0.calls.append(.startWaking) }
    }

    public func stopWaking() async {
        state.withLock { $0.calls.append(.stopWaking) }
    }

    public func forget() async {
        state.withLock {
            $0.isSetUp = false
            $0.calls.append(.forget)
        }
    }
}
