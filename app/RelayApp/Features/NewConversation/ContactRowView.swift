import Presentation
import SwiftUI

struct ContactRowView: View {
    let row: ContactRow

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(initials: row.initials, seed: row.name, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name).lineLimit(1)
                Text(row.number).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
