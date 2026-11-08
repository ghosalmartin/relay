import MessagingDomain

/// On launch: reconnect with saved credentials if there are any, otherwise ask for pairing.
public struct StartSession: Sendable {
    public enum Outcome: Equatable, Sendable {
        case connected
        case needsPairing
    }

    private let client: any MessagingClient
    private let store: any SessionStore

    public init(client: any MessagingClient, store: any SessionStore) {
        self.client = client
        self.store = store
    }

    public func callAsFunction() async throws -> Outcome {
        guard let session = try await store.load() else {
            return .needsPairing
        }
        do {
            try await client.connect(using: session)
            return .connected
        } catch .notPaired {
            try await store.clear()
            return .needsPairing
        }
    }
}
