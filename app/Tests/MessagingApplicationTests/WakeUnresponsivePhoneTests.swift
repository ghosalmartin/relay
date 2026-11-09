import MessagingApplication
import MessagingDomain
import MessagingTestSupport
import Testing

@Suite struct WakeUnresponsivePhoneTests {
    private struct Harness {
        let waker: FakePhoneWaker
        let clock = ManualClock()
        let needsWaking = LiveValue(false)

        init(isSetUp: Bool = true) {
            waker = FakePhoneWaker(isSetUp: isSetUp)
        }

        func start() -> Task<Void, Never> {
            let wake = WakeUnresponsivePhone(needsWaking: needsWaking, waker: waker, clock: clock)
            return Task { await wake() }
        }

        var attempts: Int { waker.calls.filter { $0 == .startWaking }.count }

        func waitForAttempt(_ number: Int) async -> Bool {
            await eventually { attempts == number && clock.sleeperCount == 1 }
        }

        func waitForGap(after attempts: Int) async -> Bool {
            await eventually { waker.calls.filter { $0 == .stopWaking }.count == attempts && clock.sleeperCount == 1 }
        }
    }

    @Test func aHealthyConnectionIsLeftAlone() async {
        let harness = Harness()
        let running = harness.start()

        harness.clock.advance(by: .seconds(3600))
        await Task.yield()

        #expect(harness.waker.calls.isEmpty)
        running.cancel()
    }

    @Test func startsAsSoonAsThePhoneStopsAnswering() async {
        let harness = Harness()
        let running = harness.start()

        harness.needsWaking.set(true)

        #expect(await harness.waitForAttempt(1))
        #expect(harness.waker.calls == [.startWaking])
        running.cancel()
    }

    @Test func stopsAsSoonAsThePhoneAnswers() async {
        let harness = Harness()
        let running = harness.start()
        harness.needsWaking.set(true)
        #expect(await harness.waitForAttempt(1))

        harness.needsWaking.set(false)

        #expect(await eventually { harness.waker.calls == [.startWaking, .stopWaking] })
        running.cancel()
    }

    @Test func givesUpOnAnAttemptIfThePhoneStaysQuiet() async {
        let harness = Harness()
        let running = harness.start()
        harness.needsWaking.set(true)
        #expect(await harness.waitForAttempt(1))

        harness.clock.advance(by: WakeUnresponsivePhone.attemptLength)

        #expect(await eventually { harness.waker.calls == [.startWaking, .stopWaking] })
        running.cancel()
    }

    @Test func aStallStraightAfterAnAnswerStillWaitsItsTurn() async {
        let harness = Harness()
        let running = harness.start()
        harness.needsWaking.set(true)
        #expect(await harness.waitForAttempt(1))
        harness.needsWaking.set(false)
        #expect(await harness.waitForGap(after: 1))

        harness.needsWaking.set(true)
        harness.clock.advance(by: .seconds(59))
        await Task.yield()
        #expect(harness.attempts == 1)

        harness.clock.advance(by: .seconds(1))
        #expect(await harness.waitForAttempt(2))
        running.cancel()
    }

    @Test func triesAgainAtLengtheningIntervals() async {
        let harness = Harness()
        let running = harness.start()
        harness.needsWaking.set(true)

        for (index, wait) in (WakeUnresponsivePhone.waits + [.seconds(1800)]).enumerated() {
            #expect(await harness.waitForAttempt(index + 1))
            harness.clock.advance(by: WakeUnresponsivePhone.attemptLength)
            #expect(await harness.waitForGap(after: index + 1))
            harness.clock.advance(by: wait)
        }
        #expect(await harness.waitForAttempt(6))
        running.cancel()
    }

    @Test func doesNothingUntilItHasBeenSetUp() async {
        let harness = Harness(isSetUp: false)
        let running = harness.start()

        harness.needsWaking.set(true)
        await Task.yield()
        harness.clock.advance(by: .seconds(3600))
        await Task.yield()

        #expect(harness.waker.calls.isEmpty)
        running.cancel()
    }
}
