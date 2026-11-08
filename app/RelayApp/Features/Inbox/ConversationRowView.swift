import Presentation
import SwiftUI

struct ConversationRowView: View {
    let row: ConversationRow

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(initials: row.initials, seed: row.title, photo: row.avatar)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.title)
                        .font(.headline.weight(row.isUnread ? .bold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(row.lastActivity, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .top) {
                    Text(row.preview)
                        .font(.subheadline)
                        .foregroundStyle(row.isUnread ? .primary : .secondary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if row.isUnread {
                        Circle().fill(.tint).frame(width: 8, height: 8).padding(.top, 4)
                            .accessibilityLabel("Unread")
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("conversation.\(row.id.rawValue)")
    }
}
