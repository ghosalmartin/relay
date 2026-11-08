import Foundation
@testable import LibGMKit
import Testing

/// Exercises the real Go library through the C ABI. No network: only paths that fail
/// or finish locally.
@Suite struct CBridgeIntegrationTests {
    @Test func rejectsACorruptSavedSession() {
        #expect(throws: LibGMError.invalidSavedSession) {
            _ = try LibGMSession(savedSession: Data("{not json".utf8))
        }
    }

    @Test func freshSessionOpensAndClosesCleanly() async throws {
        let session = try LibGMSession(savedSession: nil)
        session.close()

        for await _ in session.events {}   // ends because close() finishes the stream
    }

    @Test func callsBeforePairingFailWithLibGMsReason() async throws {
        let session = try LibGMSession(savedSession: nil)
        defer { session.close() }

        await #expect {
            try await session.markRead(conversationID: "c1", messageID: "m1")
        } throws: { error in
            guard case LibGMError.bridge(let reason) = error else { return false }
            return !reason.isEmpty
        }
    }
}
