import MessagingDomain
import SwiftUI

/// The small mark under my latest message: sending, sent, delivered, read or failed.
struct DeliveryStatusView: View {
    let status: DeliveryStatus

    var body: some View {
        Label(title, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption2)
            .foregroundStyle(status == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
    }

    private var title: String {
        switch status {
        case .sending: "Sending"
        case .sent: "Sent"
        case .delivered: "Delivered"
        case .read: "Read"
        case .failed: "Not sent"
        case .received, .deleted: ""
        }
    }

    private var symbol: String {
        switch status {
        case .sending: "clock"
        case .sent: "checkmark"
        case .delivered: "checkmark.circle"
        case .read: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle"
        case .received, .deleted: ""
        }
    }
}
