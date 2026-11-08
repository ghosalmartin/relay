import Presentation
import SwiftUI

/// One message bubble. Mine sit right in the accent colour; theirs sit left in grey.
struct MessageBubbleView: View {
    let bubble: MessageBubble

    var body: some View {
        HStack {
            if bubble.isFromMe { Spacer(minLength: 64) }
            VStack(alignment: bubble.isFromMe ? .trailing : .leading, spacing: 3) {
                if let sender = bubble.senderName {
                    Text(sender).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                content
                footer
            }
            if !bubble.isFromMe { Spacer(minLength: 64) }
        }
        .padding(.bottom, bubble.endsBurst ? 8 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("message.\(bubble.id.rawValue)")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(bubble.attachments, id: \.id) { attachment in
                Label(attachment.fileName.isEmpty ? "Attachment" : attachment.fileName,
                      systemImage: attachment.isImage ? "photo" : "doc")
            }
            if !bubble.text.isEmpty {
                Text(bubble.text).textSelection(.enabled)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .foregroundStyle(bubble.isFromMe ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .background(bubbleFill, in: .rect(cornerRadius: 16))
    }

    @ViewBuilder
    private var footer: some View {
        if bubble.endsBurst || bubble.status != nil {
            HStack(spacing: 6) {
                if bubble.endsBurst {
                    Text(bubble.sentAt, format: .dateTime.hour().minute())
                }
                if let status = bubble.status {
                    DeliveryStatusView(status: status)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var bubbleFill: AnyShapeStyle {
        bubble.isFromMe ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary)
    }
}
