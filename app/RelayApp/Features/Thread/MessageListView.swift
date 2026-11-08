import MessagingDomain
import Presentation
import SwiftUI

/// The scrolling column of day separators and bubbles, pinned to the newest message.
struct MessageListView: View {
    let items: [ThreadItem]
    let canLoadOlder: Bool
    let isLoadingOlder: Bool
    let onLoadOlder: () -> Void
    let attachments: [String: AttachmentContent]
    let onAttachmentAppear: (Attachment) -> Void
    let onAttachmentTap: (Attachment) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                olderHistory
                ForEach(items) { item in
                    switch item {
                    case .daySeparator(let day):
                        DaySeparatorView(day: day)
                    case .bubble(let bubble):
                        MessageBubbleView(
                            bubble: bubble,
                            attachments: attachments,
                            onAttachmentAppear: onAttachmentAppear,
                            onAttachmentTap: onAttachmentTap
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .defaultScrollAnchor(.bottom)
        .accessibilityIdentifier("thread.messages")
    }

    @ViewBuilder
    private var olderHistory: some View {
        if isLoadingOlder {
            ProgressView().controlSize(.small).padding(8)
        } else if canLoadOlder {
            Button("Load Earlier Messages", action: onLoadOlder)
                .buttonStyle(.link)
                .padding(8)
        }
    }
}

private struct DaySeparatorView: View {
    let day: Date

    var body: some View {
        Text(day, format: .dateTime.weekday(.wide).day().month(.wide))
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.vertical, 12)
    }
}
