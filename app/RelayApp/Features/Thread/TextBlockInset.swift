import SwiftUI

/// The padding around text inside a bubble.
struct TextBlockInset: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, MessageBubbleView.textInset)
            .padding(.vertical, MessageBubbleView.lineInset)
    }
}
