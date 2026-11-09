import Foundation
import MessagingDomain

/// Fetches contact photos for the people in the inbox.
public struct LoadAvatars: Sendable {
    private let client: any MessagingClient
    private let book: AvatarBook

    public init(client: any MessagingClient, book: AvatarBook = AvatarBook()) {
        self.client = client
        self.book = book
    }

    public func callAsFunction(_ participants: Set<ParticipantID>) async throws(MessagingError) -> [ParticipantID: Data] {
        let photos = try await client.avatars(for: participants)
        book.add(photos)
        return photos
    }
}
