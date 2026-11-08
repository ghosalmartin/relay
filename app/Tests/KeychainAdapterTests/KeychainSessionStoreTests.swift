import Foundation
import KeychainAdapter
import MessagingDomain
import Testing

/// Runs against the real login Keychain under a throwaway service name.
@Suite(.serialized) struct KeychainSessionStoreTests {
    private let store = KeychainSessionStore(service: "dev.featurenotabug.relay.tests.\(UUID().uuidString)")

    @Test func savesLoadsOverwritesAndClears() async throws {
        #expect(try await store.load() == nil)

        try await store.save(SessionData(bytes: Data("one".utf8)))
        #expect(try await store.load() == SessionData(bytes: Data("one".utf8)))

        try await store.save(SessionData(bytes: Data("two".utf8)))
        #expect(try await store.load() == SessionData(bytes: Data("two".utf8)))

        try await store.clear()
        #expect(try await store.load() == nil)
    }

    @Test func clearingAnEmptyStoreIsFine() async throws {
        try await store.clear()
    }
}
