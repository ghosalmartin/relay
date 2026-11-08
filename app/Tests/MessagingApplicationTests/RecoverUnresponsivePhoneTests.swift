import MessagingApplication
import MessagingDomain
import MessagingTestSupport
import Testing

@Suite struct RecoverUnresponsivePhoneTests {
    private struct Harness {
        let client = FakeMessagingClient()
        let clock = ManualClock()
        let connection = LiveValue(ConnectionStatus.online)
        let store: InMemorySessionStore

        init(store: InMemorySessionStore = InMemorySessionStore(Fixtures.session)) {
            self.store = store
        }

        func start() -> Task<Void, Never> {
            let recover = RecoverUnresponsivePhone(
                connection: connection,
                startSession: StartSession(client: client, store: store),
                clock: clock
            )
            return Task { await recover() }
        }

        var reconnects: Int { client.calls.filter { $0 == .connect(Fixtures.session) }.count }

        func waitForTimer() async -> Bool {
            await eventually { clock.sleeperCount == 1 }
        }
    }

    @Test func aHealthyConnectionIsLeftAlone() async {
        let harness = Harness()
        let running = harness.start()

        harness.clock.advance(by: .seconds(3600))
        await Task.yield()

        #expect(harness.reconnects == 0)
        running.cancel()
    }

    @Test func reconnectsOnceThePhoneHasBeenQuietForAMinute() async {
        let harness = Harness()
        let running = harness.start()
        harness.connection.set(.phoneUnreachable)
        #expect(await harness.waitForTimer())

        harness.clock.advance(by: .seconds(59))
        #expect(harness.reconnects == 0)
        harness.clock.advance(by: .seconds(1))

        #expect(await eventually { harness.reconnects == 1 })
        running.cancel()
    }

    @Test func doesNothingIfThePhoneCameBackDuringTheWait() async {
        let harness = Harness()
        let running = harness.start()
        harness.connection.set(.phoneUnreachable)
        #expect(await harness.waitForTimer())

        harness.connection.set(.online)
        harness.clock.advance(by: .seconds(60))

        #expect(await eventually { harness.clock.sleeperCount == 0 })
        #expect(harness.reconnects == 0)
        running.cancel()
    }

    @Test func keepsTryingAtLengtheningIntervals() async {
        let harness = Harness()
        let running = harness.start()
        harness.connection.set(.phoneUnreachable)

        for (index, wait) in (RecoverUnresponsivePhone.waits + [.seconds(900)]).enumerated() {
            #expect(await harness.waitForTimer())
            harness.clock.advance(by: wait)
            #expect(await eventually { harness.reconnects == index + 1 })
        }
        running.cancel()
    }

    @Test func stopsWhenThereIsNoSavedLogin() async {
        let harness = Harness(store: InMemorySessionStore())
        let running = harness.start()
        harness.connection.set(.phoneUnreachable)
        #expect(await harness.waitForTimer())

        harness.clock.advance(by: .seconds(60))

        #expect(await eventually { harness.clock.sleeperCount == 0 })
        #expect(harness.client.calls.isEmpty)
        running.cancel()
    }

    @Test func aFailedAttemptIsTriedAgain() async {
        let harness = Harness()
        harness.client.stubConnect(throwing: .phoneUnreachable)
        let running = harness.start()
        harness.connection.set(.phoneUnreachable)
        #expect(await harness.waitForTimer())
        harness.clock.advance(by: .seconds(60))
        #expect(await eventually { harness.reconnects == 1 })

        #expect(await harness.waitForTimer())
        harness.clock.advance(by: .seconds(120))

        #expect(await eventually { harness.reconnects == 2 })
        running.cancel()
    }
}
