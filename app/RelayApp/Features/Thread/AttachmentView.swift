import MessagingDomain
import Presentation
import SwiftUI

/// A picture drawn in the bubble, or a card for any other kind of file.
struct AttachmentView: View {
    let attachment: Attachment
    let content: AttachmentContent?
    let onAppear: () -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            if attachment.isImage { picture } else { fileCard }
        }
        .buttonStyle(.plain)
        .disabled(!attachment.canOpen)
        .onAppear { if attachment.isImage { onAppear() } }
    }

    @ViewBuilder
    private var picture: some View {
        switch content {
        case .loaded(let data):
            LoadedPicture(data: data)
        case .failed:
            Label("Couldn't load picture. Click to retry.", systemImage: "exclamationmark.triangle")
        case .loading, nil:
            ProgressView().frame(width: 200, height: 140)
        }
    }

    private var fileCard: some View {
        HStack(spacing: 8) {
            if content == .loading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: attachment.symbolName(showing: content))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.displayName).lineLimit(1)
                if let size = attachment.sizeText {
                    Text(size).font(.caption)
                }
            }
        }
    }
}
