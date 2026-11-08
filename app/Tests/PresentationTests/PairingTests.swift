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
    @Test func showsTheCodeThenReportsPairing() async {
        let client = FakeMessagingClient()
        client.stubEventsOnStartPairing([.pairingCode("qr-1"), .paired])
        let pairedCount = LiveValue(0)
        let viewModel = PairingViewModel(pairDevice: PairDevice(client: client, clock: ManualClock())) {
            pairedCount.update { $0 + 1 }
        }

        await viewModel.run()

        #expect(viewModel.state.step == .paired)
        #expect(pairedCount.value == 1)
    }

    @Test func retryChangesTheRunID() {
        let viewModel = PairingViewModel(pairDevice: PairDevice(client: FakeMessagingClient())) {}
        let before = viewModel.runID

        viewModel.send(.retryTapped)

        #expect(viewModel.runID != before)
    }
}
