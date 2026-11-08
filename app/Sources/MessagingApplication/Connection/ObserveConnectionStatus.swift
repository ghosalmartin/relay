import MessagingDomain

/// Streams connection status changes, starting from `.connecting`. Repeats are dropped.
public struct ObserveConnectionStatus: Sendable {
    private let client: any MessagingClient

    public init(client: any MessagingClient) {
        self.client = client
    }

    public func callAsFunction() -> AsyncStream<ConnectionStatus> {
        let events = client.events()
        return AsyncStream { continuation in
            let task = Task {
                var current = ConnectionStatus.connecting
                continuation.yield(current)
                for await event in events {
                    guard let next = ConnectionStatus.after(event), next != current else { continue }
                    current = next
                    continuation.yield(next)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
