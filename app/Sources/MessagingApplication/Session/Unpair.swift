import MessagingDomain

/// Removes this device from the phone and forgets the saved session.
public struct Unpair: Sendable {
    private let client: any MessagingClient
    private let store: any SessionStore

    public init(client: any MessagingClient, store: any SessionStore) {
        self.client = client
        self.store = store
    }

    public func callAsFunction() async throws {
        try await client.unpair()
        try await store.clear()
    }
}
