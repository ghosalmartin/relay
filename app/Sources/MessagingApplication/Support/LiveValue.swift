import Synchronization

/// A value that changes over time. Unlike an event stream, a subscriber always starts with
/// the current value, so it doesn't matter how late a screen turns up.
public final class LiveValue<Value: Sendable & Equatable>: Sendable {
    private struct State {
        var value: Value
        var nextSubscriber = 0
        var subscribers: [Int: AsyncStream<Value>.Continuation] = [:]
    }

    private let state: Mutex<State>

    public init(_ initial: Value) {
        state = Mutex(State(value: initial))
    }

    public var value: Value { state.withLock { $0.value } }

    public func set(_ newValue: Value) {
        update { _ in newValue }
    }

    /// Replaces the value with `change(value)` atomically and tells subscribers if it is different.
    public func update(_ change: (Value) -> Value) {
        state.withLock { state in
            let updated = change(state.value)
            guard updated != state.value else { return }
            state.value = updated
            state.subscribers.values.forEach { $0.yield(updated) }
        }
    }

    /// The current value, then every change until the caller's task is cancelled.
    public func values() -> AsyncStream<Value> {
        let (stream, continuation) = AsyncStream.makeStream(of: Value.self)
        // Registering and yielding under one lock means no change can fall between them.
        let id = state.withLock { state in
            let id = state.nextSubscriber
            state.nextSubscriber += 1
            state.subscribers[id] = continuation
            continuation.yield(state.value)
            return id
        }
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { _ = $0.subscribers.removeValue(forKey: id) }
        }
        return stream
    }
}
