import MessagingDomain

/// Fetches the phone's address book, to pick someone to message.
public struct LoadContacts: Sendable {
    private let client: any MessagingClient

    public init(client: any MessagingClient) {
        self.client = client
    }

    public func callAsFunction() async throws(MessagingError) -> [Contact] {
        try await client.contacts()
    }
}
