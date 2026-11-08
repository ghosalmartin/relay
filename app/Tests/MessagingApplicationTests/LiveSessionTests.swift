@testable import MessagingApplication
import MessagingDomain
import MessagingTestSupport
import Testing

@Suite struct LiveValueTests {
    @Test func aLateSubscriberStartsWithTheCurrentValueThenFollowsChanges() async {
        let value = LiveValue(1)
        value.set(2)

        let stream = value.values()
        value.set(3)

        #expect(await stream.first(2) == [2, 3])
    }

    @Test func settingTheSameValueIsNotAChange() async {
        let value = LiveValue(1)
        let stream = value.values()

        value.set(1)
        value.set(2)

        #expect(await stream.first(2) == [1, 2])
    }
}

@Suite struct LiveSessionTests {
    @Test func holdsTheInboxForScreensThatAppearAfterTheBurst() async {
        let client = FakeMessagingClient()
        let session = LiveSession(client: client)
        client.emit(.conversationUpdated(Fixtures.conversation("c1", title: "Sam")))   // nothing is running yet
        client.emit(.initialSyncCompleted)
        let pump = Task { await session.run() }

        #expect(await eventually { !session.inbox.value.isSyncing })

        let snapshots = ObserveInbox(session: session)()
        let first = await snapshots.first(1)
        #expect(first.first?.conversations.map(\.title) == ["Sam"])
        pump.cancel()
    }

    @Test func aNewPairingStartsFromAClearInboxAndConnection() async {
        let client = FakeMessagingClient()
        let session = LiveSession(client: client)
        let pump = Task { await session.run() }
        client.emit(.conversationUpdated(Fixtures.conversation("old-phone")))
        client.emit(.initialSyncCompleted)
        client.emit(.loggedOut)
        #expect(await eventually { session.connection.value == .loggedOut })

        client.emit(.paired)

        #expect(await eventually { session.connection.value == .connecting })
        #expect(session.inbox.value == InboxSnapshot(conversations: [], isSyncing: true))
        pump.cancel()
    }
}

@Suite struct UnpairFailureTests {
    @Test func forgetsTheSessionEvenIfThePhoneCannotBeTold() async {
        let client = FakeMessagingClient()
        client.stubUnpair(throwing: .phoneUnreachable)
        let store = InMemorySessionStore(Fixtures.session)

        await #expect(throws: MessagingError.phoneUnreachable) {
            try await Unpair(client: client, store: store)()
        }

        #expect(store.session == nil)
    }
}

@Suite struct PersistSessionChangesRaceTests {
    @Test func savesAChangeThatHappensBeforeItStartsRunning() async {
        let client = FakeMessagingClient()
        let store = InMemorySessionStore()
        let persist = PersistSessionChanges(client: client, store: store)

        client.emit(.sessionChanged(Fixtures.session))
        let task = Task { await persist() }

        #expect(await eventually { store.session == Fixtures.session })
        task.cancel()
    }
}
