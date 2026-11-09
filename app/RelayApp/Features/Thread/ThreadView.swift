import MessagingDomain
import Presentation
import SwiftUI

/// One conversation: history, live messages and the composer.
struct ThreadView: View {
    let conversation: Conversation
    @State private var viewModel: ThreadViewModel

    init(environment: AppEnvironment, conversation: Conversation) {
        self.conversation = conversation
        _viewModel = State(initialValue: environment.makeThreadViewModel(for: conversation))
    }

    var body: some View {
        VStack(spacing: 0) {
            messages
            if let notice = viewModel.state.waitingNotice {
                WaitingForPhoneView(notice: notice, onDismiss: { viewModel.send(.waitingDismissed) })
            }
            Divider()
            ComposerView(
                draft: Binding(get: { viewModel.state.draft }, set: { viewModel.send(.draftChanged($0)) }),
                canSend: viewModel.state.canSend,
                files: viewModel.state.pendingFiles,
                replyPreview: viewModel.state.replyPreview,
                onCancelReply: { viewModel.send(.replyCancelled) },
                onSend: { viewModel.send(.sendTapped) },
                onFile: { viewModel.send(.fileRead($0)) },
                onRemoveFile: { viewModel.send(.fileRemoved($0)) }
            )
        }
        .dropDestination(for: URL.self) { urls, _ in
            urls.forEach { viewModel.send(.fileRead(OutgoingAttachmentReader.read($0))) }
            return !urls.isEmpty
        }
        .confirmationDialog(
            "Delete this message?",
            isPresented: Binding(get: { viewModel.state.confirmingDelete != nil }, set: { if !$0 { viewModel.send(.deleteCancelled) } }),
            actions: {
                Button("Delete", role: .destructive) { viewModel.send(.deleteConfirmed) }
                Button("Cancel", role: .cancel) { viewModel.send(.deleteCancelled) }
            },
            message: { Text("It will be deleted from your phone as well.") }
        )
        .navigationTitle(viewModel.state.title)
        .task { await viewModel.run() }
        .onChange(of: conversation) { _, updated in viewModel.send(.conversationChanged(updated)) }
        .alert(
            "That didn't work",
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
                onLoadOlder: { viewModel.send(.loadOlderTapped) },
                attachments: viewModel.state.attachments,
                onAttachmentAppear: { viewModel.send(.attachmentAppeared($0)) },
                onAttachmentTap: { viewModel.send(.attachmentTapped($0)) },
                actions: MessageActions(
                    reply: { viewModel.send(.replyTapped($0)) },
                    react: { viewModel.send(.reactionChosen($0, $1)) },
                    delete: { viewModel.send(.deleteTapped($0)) },
                    openFile: { viewModel.send(.attachmentOpenTapped($0)) }
                )
            )
        }
    }
}
