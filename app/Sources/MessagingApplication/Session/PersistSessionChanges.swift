import MessagingDomain

/// Keeps the stored credentials in step with the client for as long as it runs:
/// saves every session change and clears the store on logout.
/// Start it once at launch, in a task that lives as long as the app.
public struct PersistSessionChanges: Sendable {
    private let client: any MessagingClient
    private let store: any SessionStore

    public init(client: any MessagingClient, store: any SessionStore) {
        self.client = client
        self.store = store
    }

    public func callAsFunction() async {
        for await event in client.events() {
            await persist(event)
        }
    }

    private func persist(_ event: MessagingEvent) async {
        do {
            switch event {
            case .sessionChanged(let session): try await store.save(session)
            case .loggedOut: try await store.clear()
            default: break
            }
        } catch {
            // The session stays valid in memory; the next change retries the save.
        }
    }
}
