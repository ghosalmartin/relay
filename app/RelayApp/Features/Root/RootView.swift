import Presentation
import SwiftUI

/// Shows pairing or the inbox, as the root view model decides.
struct RootView: View {
    let environment: AppEnvironment
    @State private var viewModel: RootViewModel

    init(environment: AppEnvironment) {
        self.environment = environment
        _viewModel = State(initialValue: environment.makeRootViewModel())
    }

    var body: some View {
        content
            .task { await viewModel.run() }
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
