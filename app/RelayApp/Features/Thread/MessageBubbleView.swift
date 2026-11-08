import MessagingDomain
import Presentation
import SwiftUI

/// One message bubble. Mine sit right in the accent colour; theirs sit left in grey.
struct MessageBubbleView: View {
    let bubble: MessageBubble
    let attachments: [String: AttachmentContent]
    let onAttachmentAppear: (Attachment) -> Void
    let onAttachmentTap: (Attachment) -> Void

    var body: some View {
        HStack {
            if bubble.isFromMe { Spacer(minLength: 64) }
            VStack(alignment: bubble.isFromMe ? .trailing : .leading, spacing: 3) {
                if let sender = bubble.senderName {
                    Text(sender).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                content
                reactions
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
            if let reply = bubble.replyPreview {
                Label(reply, systemImage: "arrowshape.turn.up.left")
                    .font(.caption)
                    .lineLimit(2)
                    .opacity(0.75)
            }
            if let placeholder = bubble.placeholder {
                Text(placeholder).italic().opacity(0.75)
            } else {
                messageBody
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .foregroundStyle(bubble.isFromMe ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .background(bubbleFill, in: .rect(cornerRadius: 16))
    }

    @ViewBuilder
    private var messageBody: some View {
        ForEach(bubble.attachments, id: \.id) { attachment in
            AttachmentView(
                attachment: attachment,
                content: attachments[attachment.id],
                onAppear: { onAttachmentAppear(attachment) },
                onTap: { onAttachmentTap(attachment) }
            )
        }
        if !bubble.text.isEmpty {
            Text(bubble.linkedText)
                .textSelection(.enabled)
                .tint(bubble.isFromMe ? .white : .accentColor)     // the accent colour would vanish on my bubbles
        }
    }

    @ViewBuilder
    private var reactions: some View {
        if !bubble.reactions.isEmpty {
            HStack(spacing: 4) {
                ForEach(bubble.reactions, id: \.emoji) { reaction in
                    Text(reaction.displayText)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.fill.secondary, in: .capsule)
                }
            }
        }
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
