import SwiftUI

/// Two members' photos overlapping, the same overall size as a single avatar.
struct GroupAvatarView: View {
    let first: Data
    let second: Data

    private static let side: CGFloat = 36
    private static let memberSide: CGFloat = 24

    var body: some View {
        ZStack {
            member(first).offset(x: -6, y: -6)
            member(second).offset(x: 6, y: 6)
        }
        .frame(width: Self.side, height: Self.side)
        .accessibilityHidden(true)
    }

    private func member(_ photo: Data) -> some View {
        AvatarView(initials: "", seed: "", photo: photo, size: Self.memberSide)
    }
}
