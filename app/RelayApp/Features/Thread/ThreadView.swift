import Presentation
import SwiftUI

/// One conversation: history, live messages and the composer.
struct ThreadView: View {
    @State var viewModel: ThreadViewModel

    var body: some View {
        VStack(spacing: 0) {
            messages
            Divider()
            ComposerView(
                draft: Binding(get: { viewModel.state.draft }, set: { viewModel.send(.draftChanged($0)) }),
                canSend: viewModel.state.canSend,
                onSend: { viewModel.send(.sendTapped) }
            )
        }
        .navigationTitle(viewModel.state.title)
        .task { await viewModel.run() }
        .alert(
            "Message not sent",
            isPresented: Binding(get: { viewModel.state.sendError != nil }, set: { if !$0 { viewModel.send(.sendErrorDismissed) } }),
            actions: { Button("OK") { viewModel.send(.sendErrorDismissed) } },
            message: { Text(viewModel.state.sendError ?? "") }
        )
    }

    @ViewBuilder
    private var messages: some View {
        switch viewModel.state.history {
        case .loading where viewModel.state.messages.isEmpty:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message) where viewModel.state.messages.isEmpty:
            ContentUnavailableView {
                Label("Couldn't load messages", systemImage: "exclamationmark.bubble")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { viewModel.send(.retryHistoryTapped) }
            }
        default:
            MessageListView(
                items: viewModel.state.items(),
                canLoadOlder: viewModel.state.canLoadOlder,
                isLoadingOlder: viewModel.state.isLoadingOlder,
                onLoadOlder: { viewModel.send(.loadOlderTapped) }
            )
        }
    }
}
