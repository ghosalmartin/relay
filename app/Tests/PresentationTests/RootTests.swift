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

    @Test func offersPhoneWakeSetupOnlyFromTheInbox() {
        #expect(RootReducer.reduce(.inbox, .phoneWakeSetupNeeded) == .settingUpPhoneWake)
        #expect(RootReducer.reduce(.pairing, .phoneWakeSetupNeeded) == .pairing)
    }

    @Test func endingPhoneWakeSetupShowsTheInbox() {
        #expect(RootReducer.reduce(.settingUpPhoneWake, .phoneWakeSetupEnded) == .inbox)
    }

    @Test func aLostLoginDuringPhoneWakeSetupGoesBackToPairing() {
        #expect(RootReducer.reduce(.settingUpPhoneWake, .connectionChanged(.loggedOut)) == .pairing)
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

    @Test func offersPhoneWakeSetupAtLaunchUntilItIsDone() async {
        let waker = FakePhoneWaker(isSetUp: false)
        let (viewModel, _, _) = makeViewModel(store: InMemorySessionStore(Fixtures.session), waker: waker)
        let running = Task { await viewModel.run() }
        #expect(await eventually { viewModel.state == .settingUpPhoneWake })

        viewModel.send(.phoneWakeSetupCompleted)

        #expect(viewModel.state == .inbox)
        #expect(waker.isSetUp)
        running.cancel()
    }

    @Test func offersPhoneWakeSetupStraightAfterPairing() {
        let (viewModel, _, _) = makeViewModel(store: InMemorySessionStore(), waker: FakePhoneWaker(isSetUp: false))

        viewModel.send(.pairingFinished)

        #expect(viewModel.state == .settingUpPhoneWake)
    }

    @Test func skippingPhoneWakeSetupDoesNotCountAsDoingIt() {
        let waker = FakePhoneWaker(isSetUp: false)
        let (viewModel, _, _) = makeViewModel(store: InMemorySessionStore(), waker: waker)
        viewModel.send(.pairingFinished)

        viewModel.send(.phoneWakeSetupSkipped)

        #expect(viewModel.state == .inbox)
        #expect(!waker.isSetUp)
    }

    private func makeViewModel(store: InMemorySessionStore, waker: FakePhoneWaker = FakePhoneWaker()) -> (RootViewModel, FakeMessagingClient, InMemorySessionStore) {
        let client = FakeMessagingClient()
        let viewModel = RootViewModel(
            startSession: StartSession(client: client, store: store),
            persistSessionChanges: PersistSessionChanges(client: client, store: store),
            observeConnectionStatus: ObserveConnectionStatus(session: LiveSession(client: client)),
            unpair: Unpair(client: client, store: store, waker: waker),
            phoneWaker: waker
        )
        return (viewModel, client, store)
    }
}
