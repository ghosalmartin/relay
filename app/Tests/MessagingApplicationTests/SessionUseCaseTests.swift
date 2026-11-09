@testable import MessagingApplication
import MessagingDomain
import MessagingTestSupport
import Testing

@Suite struct StartSessionTests {
    @Test func withoutSavedSessionAsksForPairing() async throws {
        let client = FakeMessagingClient()

        let outcome = try await StartSession(client: client, store: InMemorySessionStore())()

        #expect(outcome == .needsPairing)
        #expect(client.calls.isEmpty)
    }

    @Test func withSavedSessionConnects() async throws {
        let client = FakeMessagingClient()

        let outcome = try await StartSession(client: client, store: InMemorySessionStore(Fixtures.session))()

        #expect(outcome == .connected)
        #expect(client.calls == [.connect(Fixtures.session)])
    }

    @Test func revokedSessionIsClearedAndPairingRequested() async throws {
        let client = FakeMessagingClient()
        client.stubConnect(throwing: .notPaired)
        let store = InMemorySessionStore(Fixtures.session)

        let outcome = try await StartSession(client: client, store: store)()

        #expect(outcome == .needsPairing)
        #expect(store.session == nil)
    }

    @Test func otherConnectFailuresPropagateAndKeepTheSession() async {
        let client = FakeMessagingClient()
        client.stubConnect(throwing: .phoneUnreachable)
        let store = InMemorySessionStore(Fixtures.session)

        await #expect(throws: MessagingError.phoneUnreachable) {
            try await StartSession(client: client, store: store)()
        }
        #expect(store.session == Fixtures.session)
    }
}

@Suite struct PersistSessionChangesTests {
    @Test func savesChangesAndClearsOnLogout() async {
        let client = FakeMessagingClient()
        let store = InMemorySessionStore()
        let task = Task { await PersistSessionChanges(client: client, store: store)() }
        #expect(await eventually { client.subscriberCount == 1 })

        client.emit(.sessionChanged(Fixtures.session))
        #expect(await eventually { store.session != nil })
        #expect(store.session == Fixtures.session)

        client.emit(.loggedOut)
        #expect(await eventually { store.session == nil })
        #expect(store.session == nil)
        task.cancel()
    }
}

@Suite struct PairDeviceTests {
    @Test func pairsWithTheCookiesShowingTheEmojiUntilPaired() async throws {
        let client = FakeMessagingClient()
        client.stubEventsOnStartPairing([.pairingConfirmationEmoji("🦊"), .sessionChanged(Fixtures.session), .paired])

        let steps = try await PairDevice(client: client)(with: Fixtures.accountCookies).reduce([PairingStep]()) { $0 + [$1] }

        #expect(steps == [.confirmEmoji("🦊"), .paired])
        #expect(client.calls.first == .startPairing(Fixtures.accountCookies))
    }

    @Test func aRefusalFromThePhoneEndsPairing() async {
        let client = FakeMessagingClient()
        client.stubEventsOnStartPairing([.pairingConfirmationEmoji("🦊")])
        client.stubPairing(throwing: .backend("incorrect emoji"))

        await #expect(throws: MessagingError.backend("incorrect emoji")) {
            for try await _ in PairDevice(client: client)(with: Fixtures.accountCookies) {}
        }
    }

    @Test func mapsOnlyPairingEvents() {
        #expect(PairDevice.step(for: .pairingConfirmationEmoji("🦊")) == .confirmEmoji("🦊"))
        #expect(PairDevice.step(for: .initialSyncCompleted) == nil)
    }
}

@Suite struct UnpairTests {
    @Test func unpairsThenForgetsTheSession() async throws {
        let client = FakeMessagingClient()
        let store = InMemorySessionStore(Fixtures.session)

        try await Unpair(client: client, store: store, waker: FakePhoneWaker())()

        #expect(client.calls == [.unpair])
        #expect(store.session == nil)
    }

    @Test func forgetsTheWebsiteLoginEvenIfThePhoneCantBeTold() async {
        let client = FakeMessagingClient()
        client.stubUnpair(throwing: .phoneUnreachable)
        let waker = FakePhoneWaker()

        try? await Unpair(client: client, store: InMemorySessionStore(Fixtures.session), waker: waker)()

        #expect(waker.calls == [.forget])
        #expect(!waker.isSetUp)
    }
}
