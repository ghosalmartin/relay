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
    @Test func showsCodesUntilPairedThenFinishes() async throws {
        let client = FakeMessagingClient()
        client.stubEventsOnStartPairing([.pairingCode("code-1"), .sessionChanged(Fixtures.session), .pairingCode("code-2"), .paired])

        var steps: [PairingStep] = []
        for try await step in PairDevice(client: client)() {
            steps.append(step)
        }

        #expect(steps == [.scanCode("code-1"), .scanCode("code-2"), .paired])
        #expect(client.calls.first == .startPairing)
    }

    @Test func refreshesTheCodeEachTimeItExpires() async throws {
        let client = FakeMessagingClient()
        let clock = ManualClock()
        let pairing = PairDevice(client: client, clock: clock)()
        let task = Task { for try await _ in pairing {} }

        for expected in 1...3 {
            #expect(await eventually { clock.sleeperCount == 1 })
            clock.advance(by: PairDevice.codeLifetime)
            #expect(await eventually { refreshes(client) == expected })
        }

        client.emit(.paired)
        try await task.value
        #expect(clock.sleeperCount == 0)
    }

    private func refreshes(_ client: FakeMessagingClient) -> Int {
        client.calls.filter { $0 == .refreshPairingCode }.count
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

        try await Unpair(client: client, store: store)()

        #expect(client.calls == [.unpair])
        #expect(store.session == nil)
    }
}
