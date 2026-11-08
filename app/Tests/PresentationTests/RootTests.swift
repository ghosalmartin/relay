import MessagingApplication
import MessagingDomain
import MessagingTestSupport
@testable import Presentation
import Testing

@Suite struct RootReducerTests {
    @Test(arguments: [
        (RootMutation.sessionStarted(.connected), RootState.inbox),
        (.sessionStarted(.needsPairing), .pairing),
        (.paired, .inbox),
        (.signedOut, .pairing),
        (.sessionFailed("disk full"), .failed(message: "disk full")),
        (.retrying, .launching),
        (.connectionChanged(.loggedOut), .pairing),
        (.connectionChanged(.lost(reason: "revoked")), .pairing),
    ])
    func movesBetweenScreens(mutation: RootMutation, expected: RootState) {
        #expect(RootReducer.reduce(.inbox, mutation) == expected)
    }

    @Test(arguments: [ConnectionStatus.online, .phoneUnreachable, .reconnecting, .connecting])
    func connectionBlipsKeepTheCurrentScreen(status: ConnectionStatus) {
        #expect(RootReducer.reduce(.inbox, .connectionChanged(status)) == .inbox)
    }
}

@MainActor @Suite struct RootViewModelTests {
    @Test func launchesIntoPairingWithoutASession() async {
        let (viewModel, _, _) = makeViewModel(store: InMemorySessionStore())
        let running = Task { await viewModel.run() }

        #expect(await eventually { viewModel.state == .pairing })
        running.cancel()
    }

    @Test func launchesIntoInboxWithASession() async {
        let (viewModel, client, _) = makeViewModel(store: InMemorySessionStore(Fixtures.session))
        let running = Task { await viewModel.run() }

        #expect(await eventually { viewModel.state == .inbox })
        #expect(client.calls == [.connect(Fixtures.session)])
        running.cancel()
    }

    @Test func signingOutUnpairsAndReturnsToPairing() async {
        let (viewModel, client, store) = makeViewModel(store: InMemorySessionStore(Fixtures.session))

        await viewModel.send(.signOutTapped).value

        #expect(viewModel.state == .pairing)
        #expect(client.calls == [.unpair])
        #expect(store.session == nil)
    }

    private func makeViewModel(store: InMemorySessionStore) -> (RootViewModel, FakeMessagingClient, InMemorySessionStore) {
        let client = FakeMessagingClient()
        let viewModel = RootViewModel(
            startSession: StartSession(client: client, store: store),
            persistSessionChanges: PersistSessionChanges(client: client, store: store),
            observeConnectionStatus: ObserveConnectionStatus(client: client),
            unpair: Unpair(client: client, store: store)
        )
        return (viewModel, client, store)
    }
}
