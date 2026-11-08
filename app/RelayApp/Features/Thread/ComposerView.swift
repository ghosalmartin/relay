import SwiftUI

/// The message field. Return sends; Option-Return adds a line, as in Messages.
struct ComposerView: View {
    @Binding var draft: String
    let canSend: Bool
    let onSend: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Text Message", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($isFocused)
                .onSubmit(send)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.background, in: .capsule)
                .overlay(Capsule().strokeBorder(.separator))
                .accessibilityIdentifier("composer.field")
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .buttonStyle(.borderless)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Send")
            .accessibilityIdentifier("composer.send")
        }
        .padding(12)
        .onAppear { isFocused = true }
    }

    private func send() {
        guard canSend else { return }
        onSend()
        isFocused = true
    }
}
