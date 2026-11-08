import Synchronization

/// Fans one source of values out to any number of subscribers, like a hot `SharedFlow`.
///
/// `AsyncStream` alone is single-consumer: two loops over one stream split the values
/// between them. Each `subscribe()` here returns its own stream that sees every value
/// sent after it subscribed. A subscriber is dropped when its loop ends or its task
/// is cancelled.
///
/// A `Mutex` rather than an actor, so `subscribe()` and `send(_:)` can be called from
/// synchronous code (such as a C callback) without hopping to an executor.
public final class Broadcaster<Element: Sendable>: Sendable {
    private struct State {
        var nextID = 0
        var subscribers: [Int: AsyncStream<Element>.Continuation] = [:]
        var isFinished = false
    }

    private let state = Mutex(State())
    private let bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy

    /// - Parameter bufferingPolicy: applied per subscriber. Unbounded by default so a slow
    ///   subscriber never loses events; pass a bounded policy for high-volume streams.
    public init(bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded) {
        self.bufferingPolicy = bufferingPolicy
    }

    public func subscribe() -> AsyncStream<Element> {
        let (stream, continuation) = AsyncStream.makeStream(of: Element.self, bufferingPolicy: bufferingPolicy)
        guard let id = register(continuation) else { return stream }
        continuation.onTermination = { [weak self] _ in self?.unregister(id) }
        return stream
    }

    public func send(_ element: Element) {
        let subscribers = state.withLock { Array($0.subscribers.values) }
        for subscriber in subscribers {
            subscriber.yield(element)
        }
    }

    /// Ends every current stream. Later subscribers get an already-finished stream.
    public func finish() {
        let subscribers = state.withLock { state in
            state.isFinished = true
            defer { state.subscribers.removeAll() }
            return Array(state.subscribers.values)
        }
        for subscriber in subscribers {
            subscriber.finish()
        }
    }

    public var subscriberCount: Int {
        state.withLock { $0.subscribers.count }
    }

    /// Returns the subscriber's ID, or nil if the broadcaster has already finished.
    private func register(_ continuation: AsyncStream<Element>.Continuation) -> Int? {
        let id = state.withLock { state -> Int? in
            guard !state.isFinished else { return nil }
            let id = state.nextID
            state.nextID += 1
            state.subscribers[id] = continuation
            return id
        }
        if id == nil { continuation.finish() }
        return id
    }

    private func unregister(_ id: Int) {
        _ = state.withLock { $0.subscribers.removeValue(forKey: id) }
    }
}
