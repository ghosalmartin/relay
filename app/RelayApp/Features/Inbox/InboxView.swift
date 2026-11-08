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
        .toolbar {
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
            }
        }
        .listStyle(.sidebar)
        .searchable(text: searchText, placement: .sidebar, prompt: "Search")
        .overlay { sidebarPlaceholder }
        .accessibilityIdentifier("inbox.list")
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

    private var searchText: Binding<String> {
        Binding(get: { viewModel.state.searchText }, set: { viewModel.send(.searchChanged($0)) })
    }
}
