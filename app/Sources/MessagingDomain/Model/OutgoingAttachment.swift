import Foundation

/// A file the user has chosen to send.
public struct OutgoingAttachment: Hashable, Sendable {
    /// A safeguard against reading and uploading something enormous. The phone or carrier may allow less.
    public static let maximumByteCount = 100 * 1024 * 1024

    public let data: Data
    public let fileName: String
    public let mimeType: String

    public init(data: Data, fileName: String, mimeType: String) {
        self.data = data
        self.fileName = fileName
        self.mimeType = mimeType
    }

    public var isImage: Bool { mimeType.hasPrefix("image/") }
}
