import MessagingDomain

/// Removes this device from the phone and forgets the saved session and everything the phone waker keeps.
public struct Unpair: Sendable {
    private let client: any MessagingClient
    private let store: any SessionStore
    private let waker: any PhoneWaker

    public init(client: any MessagingClient, store: any SessionStore, waker: any PhoneWaker) {
        self.client = client
        self.store = store
        self.waker = waker
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
        await waker.forget()
        try await store.clear()
        try phoneOutcome.get()
    }
}
