import Foundation
import MessagingDomain

/// Fetches contact photos for the people in the inbox.
public struct LoadAvatars: Sendable {
    private let client: any MessagingClient

    public init(client: any MessagingClient) {
        self.client = client
    }

    public func callAsFunction(_ participants: Set<ParticipantID>) async throws(MessagingError) -> [ParticipantID: Data] {
        try await client.avatars(for: participants)
    }
}
