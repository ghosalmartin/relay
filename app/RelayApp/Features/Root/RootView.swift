import Presentation
import SwiftUI

/// Shows pairing or the inbox, as the root view model decides.
struct RootView: View {
    let environment: AppEnvironment

    private var viewModel: RootViewModel { environment.rootViewModel }

    var body: some View {
        content
            .animation(.default, value: viewModel.state)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .launching:
            ProgressView()
        case .pairing:
            PairingView(viewModel: environment.makePairingViewModel { viewModel.send(.pairingFinished) })
        case .inbox:
            InboxView(environment: environment, onSignOut: { viewModel.send(.signOutTapped) })
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't start", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { viewModel.send(.retryTapped) }
            }
        }
    }
}
