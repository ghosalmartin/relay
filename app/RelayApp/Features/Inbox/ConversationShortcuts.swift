import SwiftUI

/// ⌘1 to ⌘9. Invisible rather than hidden, because SwiftUI turns off the shortcuts of hidden buttons.
struct ConversationShortcuts: View {
    let onPress: (Int) -> Void

    var body: some View {
        ForEach(1...9, id: \.self) { position in
            Button("") { onPress(position) }
                .keyboardShortcut(KeyEquivalent(Character(String(position))))
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}
