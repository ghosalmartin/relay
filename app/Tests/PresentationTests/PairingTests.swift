import MessagingApplication
import MessagingDomain
import MessagingTestSupport
@testable import Presentation
import Testing

@Suite struct PairingReducerTests {
    @Test func failureThenRestartGoesBackToPreparing() {
        let failed = PairingReducer.reduce(PairingState(), .failed("offline"))
        #expect(failed.step == .failed(message: "offline"))

        #expect(PairingReducer.reduce(failed, .started).step == .preparing)
    }
}

@MainActor @Suite struct PairingViewModelTests {
    @Test func pairsAfterSigningInThenReports() async {
        let client = FakeMessagingClient()
        client.stubEventsOnStartPairing([.pairingConfirmationEmoji("🦊"), .paired])
        let pairedCount = LiveValue(0)
        let viewModel = PairingViewModel(pairDevice: PairDevice(client: client)) {
            pairedCount.update { $0 + 1 }
        }

        await viewModel.send(.signedIn(Fixtures.accountCookies)).value

        #expect(viewModel.state.step == .paired)
        #expect(pairedCount.value == 1)
    }

    @Test func aSecondSignInReportIsIgnored() async {
        let client = FakeMessagingClient()
        client.stubEventsOnStartPairing([.paired])
        let viewModel = PairingViewModel(pairDevice: PairDevice(client: client)) {}

        await viewModel.send(.signedIn(Fixtures.accountCookies)).value
        await viewModel.send(.signedIn(Fixtures.accountCookies)).value

        #expect(client.calls == [.startPairing(Fixtures.accountCookies)])
    }

    @Test func aFailureExplainsAndARetryGoesBackToSignIn() async {
        let client = FakeMessagingClient()
        client.stubPairing(throwing: .backend("no devices found"))
        let viewModel = PairingViewModel(pairDevice: PairDevice(client: client)) {}

        await viewModel.send(.signedIn(Fixtures.accountCookies)).value
        #expect(viewModel.state.step == .failed(message: "no devices found"))

        viewModel.send(.retryTapped)
        #expect(viewModel.state.step == .signIn)
    }

    @Test func scriptedSignInSkipsTheWebPage() async {
        let client = FakeMessagingClient()
        client.stubEventsOnStartPairing([.paired])
        let viewModel = PairingViewModel(pairDevice: PairDevice(client: client), scriptedSignIn: Fixtures.accountCookies) {}

        await viewModel.run()

        #expect(viewModel.showsWebSignIn == false)
        #expect(client.calls == [.startPairing(Fixtures.accountCookies)])
    }

    private func pasting(_ clipboard: String?, cleared: LiveValue<Int>, client: FakeMessagingClient) -> PairingViewModel {
        PairingViewModel(
            pairDevice: PairDevice(client: client),
            cookiePaste: CookiePaste(
                read: { clipboard },
                clear: { cleared.update { $0 + 1 } },
                parse: { $0 == "good curl" ? Fixtures.accountCookies : nil }
            )
        ) {}
    }

    @Test func pastingAGoodCommandPairsAndWipesTheClipboard() async {
        let client = FakeMessagingClient()
        client.stubEventsOnStartPairing([.paired])
        let cleared = LiveValue(0)

        await pasting("good curl", cleared: cleared, client: client).send(.pasteTapped).value

        #expect(client.calls == [.startPairing(Fixtures.accountCookies)])
        #expect(cleared.value == 1)
    }

    @Test(arguments: ["my shopping list", nil] as [String?])
    func pastingAnythingElseExplainsAndLeavesTheClipboard(clipboard: String?) async {
        let client = FakeMessagingClient()
        let cleared = LiveValue(0)
        let viewModel = pasting(clipboard, cleared: cleared, client: client)

        await viewModel.send(.pasteTapped).value

        #expect(viewModel.state.pasteProblem == PairingReducer.unusablePaste)
        #expect(viewModel.state.step == .signIn)
        #expect(client.calls.isEmpty)
        #expect(cleared.value == 0)
    }

    @Test func aRetryRemembersHowYouChoseToSignIn() {
        let viewModel = PairingViewModel(pairDevice: PairDevice(client: FakeMessagingClient())) {}
        #expect(viewModel.state.signInMethod == .embedded)

        viewModel.send(.signInMethodChosen(.browser))
        viewModel.send(.retryTapped)

        #expect(viewModel.state.signInMethod == .browser)
    }

    @Test func retryChangesTheRunID() {
        let viewModel = PairingViewModel(pairDevice: PairDevice(client: FakeMessagingClient())) {}
        let before = viewModel.runID

        viewModel.send(.retryTapped)

        #expect(viewModel.runID != before)
    }
}
