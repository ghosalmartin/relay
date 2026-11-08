import AsyncBroadcast
import Testing

@Suite struct BroadcasterTests {
    @Test func everySubscriberSeesEveryValue() async {
        let broadcaster = Broadcaster<Int>()
        let first = broadcaster.subscribe()
        let second = broadcaster.subscribe()

        [1, 2, 3].forEach(broadcaster.send)
        broadcaster.finish()

        #expect(await collect(first) == [1, 2, 3])
        #expect(await collect(second) == [1, 2, 3])
    }

    @Test func subscribersOnlySeeValuesSentAfterTheySubscribed() async {
        let broadcaster = Broadcaster<Int>()
        broadcaster.send(1)
        let late = broadcaster.subscribe()

        broadcaster.send(2)
        broadcaster.finish()

        #expect(await collect(late) == [2])
    }

    @Test func cancellingASubscriberRemovesIt() async {
        let broadcaster = Broadcaster<Int>()
        let stream = broadcaster.subscribe()
        let task = Task { for await _ in stream {} }
        #expect(broadcaster.subscriberCount == 1)

        task.cancel()
        await task.value

        #expect(broadcaster.subscriberCount == 0)
    }

    @Test func subscribingAfterFinishGivesAnEndedStream() async {
        let broadcaster = Broadcaster<Int>()
        broadcaster.finish()

        #expect(await collect(broadcaster.subscribe()) == [])
        #expect(broadcaster.subscriberCount == 0)
    }

    private func collect(_ stream: AsyncStream<Int>) async -> [Int] {
        var values: [Int] = []
        for await value in stream { values.append(value) }
        return values
    }
}
