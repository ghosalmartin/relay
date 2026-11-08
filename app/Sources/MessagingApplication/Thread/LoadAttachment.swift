import Foundation
import MessagingDomain

/// Fetches the contents of a file attached to a message.
public struct LoadAttachment: Sendable {
    private let client: any MessagingClient

    public init(client: any MessagingClient) {
        self.client = client
    }

    public func callAsFunction(_ attachment: Attachment) async throws(MessagingError) -> Data {
        try await client.attachmentData(attachment)
    }
}
