import AppKit
import MessagingDomain
import SwiftUI

/// The file waiting to be sent, shown above the message field so it can be checked or removed.
struct PendingAttachmentView: View {
    let attachment: OutgoingAttachment
    let sizeText: String?
    let onRemove: () -> Void
    @State private var preview: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.fileName).lineLimit(1)
                if let sizeText {
                    Text(sizeText).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Remove")
            .accessibilityLabel("Remove attachment")
            .accessibilityIdentifier("composer.removeAttachment")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .task(id: attachment) { preview = attachment.isImage ? NSImage(data: attachment.data) : nil }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let preview {
            Image(nsImage: preview)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 6))
        } else {
            Image(systemName: "doc").font(.title2).frame(width: 44, height: 44)
        }
    }
}
