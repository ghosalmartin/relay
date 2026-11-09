import MessagingDomain
import Presentation
import SwiftUI

/// Sidebar of conversations beside the selected thread.
struct InboxView: View {
    let environment: AppEnvironment
    let onSignOut: () -> Void
    @State private var viewModel: InboxViewModel

    init(environment: AppEnvironment, onSignOut: @escaping () -> Void) {
        self.environment = environment
        self.onSignOut = onSignOut
        _viewModel = State(initialValue: environment.makeInboxViewModel())
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 420)
        } detail: {
            detail
        }
        .task { await viewModel.run() }
        .confirmationDialog(
            "Delete this conversation?",
            isPresented: isConfirmingDelete,
            actions: {
                Button("Delete", role: .destructive) { viewModel.send(.deleteConfirmed) }
                Button("Cancel", role: .cancel) { viewModel.send(.deleteCancelled) }
            },
            message: { Text("It will be deleted from your phone as well.") }
        )
        .alert(
            "That didn't work",
            isPresented: hasActionError,
            actions: { Button("OK") { viewModel.send(.actionErrorDismissed) } },
            message: { Text(viewModel.state.actionError ?? "") }
        )
        .sheet(isPresented: isComposing) {
            NewConversationView(viewModel: environment.makeNewConversationViewModel()) {
                viewModel.send(.composeDismissed)
            }
        }
        .toolbar {
            ToolbarItem {
                Button { viewModel.send(.composeTapped) } label: {
                    Label("New Message", systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n")
                .help("New Message")
                .accessibilityIdentifier("inbox.compose")
            }
            ToolbarItem {
                Menu {
                    Button("Unpair This Mac", role: .destructive, action: onSignOut)
                } label: {
                    Label("Account", systemImage: "iphone.and.arrow.forward")
                }
            }
        }
    }

    private var sidebar: some View {
        List(selection: selection) {
            if let banner = viewModel.state.banner {
                ConnectionBannerView(banner: banner)
            }
            ForEach(viewModel.state.rows) { row in
                ConversationRowView(row: row)
                    .tag(row.id)
                    .contextMenu { rowMenu(row.id) }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: searchText, placement: .sidebar, prompt: "Search")
        .overlay { sidebarPlaceholder }
        .accessibilityIdentifier("inbox.list")
        .background { ConversationShortcuts { viewModel.send(.shortcutPressed($0)) } }
    }

    @ViewBuilder
    private var sidebarPlaceholder: some View {
        if viewModel.state.isSyncing && viewModel.state.rows.isEmpty {
            ProgressView("Loading conversations…")
        } else if viewModel.state.isEmpty {
            ContentUnavailableView("No Conversations", systemImage: "bubble.left.and.bubble.right")
        } else if viewModel.state.rows.isEmpty {
            ContentUnavailableView.search(text: viewModel.state.searchText)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let conversation = viewModel.state.selectedConversation {
            ThreadView(environment: environment, conversation: conversation)
                .id(conversation.id)
        } else {
            ContentUnavailableView("Select a Conversation", systemImage: "bubble.left")
        }
    }

    private var selection: Binding<ConversationID?> {
        Binding(get: { viewModel.state.selection }, set: { viewModel.send(.selected($0)) })
    }

    @ViewBuilder
    private func rowMenu(_ id: ConversationID) -> some View {
        Button("Mute") { viewModel.send(.muteTapped(id, isMuted: true)) }
        Button("Unmute") { viewModel.send(.muteTapped(id, isMuted: false)) }
        Divider()
        Button("Archive") { viewModel.send(.archiveTapped(id)) }
        Button("Delete…", role: .destructive) { viewModel.send(.deleteTapped(id)) }
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(get: { viewModel.state.confirmingDelete != nil }, set: { if !$0 { viewModel.send(.deleteCancelled) } })
    }

    private var hasActionError: Binding<Bool> {
        Binding(get: { viewModel.state.actionError != nil }, set: { if !$0 { viewModel.send(.actionErrorDismissed) } })
    }

    private var isComposing: Binding<Bool> {
        Binding(get: { viewModel.state.isComposing }, set: { viewModel.send($0 ? .composeTapped : .composeDismissed) })
    }

    private var searchText: Binding<String> {
        Binding(get: { viewModel.state.searchText }, set: { viewModel.send(.searchChanged($0)) })
    }
}
