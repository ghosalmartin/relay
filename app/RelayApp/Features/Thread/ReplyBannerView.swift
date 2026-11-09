import SwiftUI

/// Above the composer while a reply is being written: what it answers, and a way out.
struct ReplyBannerView: View {
    let preview: String
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Label(preview, systemImage: "arrowshape.turn.up.left")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .help("Cancel Reply")
            .accessibilityLabel("Cancel reply")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityIdentifier("composer.reply")
    }
}
