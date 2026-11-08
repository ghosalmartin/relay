import Foundation

/// Opaque credentials that let a client reconnect without pairing again.
/// The domain never looks inside; it only stores and hands back what the client gave it.
public struct SessionData: Hashable, Sendable {
    public let bytes: Data
    public init(bytes: Data) { self.bytes = bytes }
}
