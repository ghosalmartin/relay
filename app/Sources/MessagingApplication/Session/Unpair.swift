import MessagingDomain

/// Removes this device from the phone and forgets the saved session.
public struct Unpair: Sendable {
    private let client: any MessagingClient
    private let store: any SessionStore

    public init(client: any MessagingClient, store: any SessionStore) {
        self.client = client
        self.store = store
    }

    /// Forgets the session even if the phone can't be told, then reports that failure.
    public func callAsFunction() async throws {
        let phoneOutcome: Result<Void, any Error>
        do {
            try await client.unpair()
            phoneOutcome = .success(())
        } catch {
            phoneOutcome = .failure(error)
        }
        try await store.clear()
        try phoneOutcome.get()
    }
}
