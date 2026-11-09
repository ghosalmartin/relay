import Presentation
import SwiftUI

/// Picks a contact, or takes a typed number, and opens that conversation.
struct NewConversationView: View {
    @State var viewModel: NewConversationViewModel
    let onClose: () -> Void
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            results
        }
        .frame(width: 380, height: 440)
        .disabled(viewModel.state.isStarting)
        .overlay { if viewModel.state.isStarting { ProgressView() } }
        .task { await viewModel.run() }
        .onAppear { isFieldFocused = true }
        .onChange(of: viewModel.state.isFinished) { _, isFinished in
            if isFinished { onClose() }
        }
        .alert(
            "Couldn't start the conversation",
            isPresented: Binding(get: { viewModel.state.startError != nil }, set: { if !$0 { viewModel.send(.errorDismissed) } }),
            actions: { Button("OK") { viewModel.send(.errorDismissed) } },
            message: { Text(viewModel.state.startError ?? "") }
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            TextField("Name or number", text: Binding(get: { viewModel.state.query }, set: { viewModel.send(.queryChanged($0)) }))
                .textFieldStyle(.roundedBorder)
                .focused($isFieldFocused)
                .onSubmit { viewModel.send(.returnPressed) }
                .accessibilityIdentifier("newConversation.field")
            Button("Cancel", action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    @ViewBuilder
    private var results: some View {
        if viewModel.state.showsLoading {
            ProgressView("Loading contacts…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                if let number = viewModel.state.typedNumber {
                    Button { viewModel.send(.numberChosen(number)) } label: {
                        Label("Message \(number)", systemImage: "phone").contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("newConversation.typedNumber")
                }
                if let failure = viewModel.state.loadFailure {
                    loadFailure(failure)
                }
                ForEach(viewModel.state.rows) { row in
                    Button { viewModel.send(.numberChosen(row.id)) } label: { ContactRowView(row: row) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("contact.\(row.id)")
                }
            }
            .listStyle(.plain)
        }
    }

    private func loadFailure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Couldn't load your contacts. \(message)").foregroundStyle(.secondary)
            Button("Try Again") { viewModel.send(.retryTapped) }
        }
    }
}
