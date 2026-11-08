import SwiftUI

/// Initials on a colour picked from the name, so each person keeps the same colour.
struct AvatarView: View {
    let initials: String
    let seed: String
    let size: CGFloat

    private static let palette: [Color] = [.blue, .green, .orange, .pink, .purple, .teal, .indigo, .brown]

    init(initials: String, seed: String, size: CGFloat = 36) {
        self.initials = initials
        self.seed = seed
        self.size = size
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: .circle)
            .accessibilityHidden(true)
    }

    private var color: Color {
        let index = seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return Self.palette[index % Self.palette.count]
    }
}
