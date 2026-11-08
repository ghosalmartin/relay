import SwiftUI

/// A contact's photo, or initials on a colour picked from the name so each person keeps the same colour.
struct AvatarView: View {
    let initials: String
    let seed: String
    let photo: Data?
    let size: CGFloat

    private static let palette: [Color] = [.blue, .green, .orange, .pink, .purple, .teal, .indigo, .brown]

    init(initials: String, seed: String, photo: Data? = nil, size: CGFloat = 36) {
        self.initials = initials
        self.seed = seed
        self.photo = photo
        self.size = size
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: .circle)
            .overlay { if let photo { AvatarPhoto(data: photo) } }     // initials stay if it can't be decoded
            .clipShape(.circle)
            .accessibilityHidden(true)
    }

    private var color: Color {
        let index = seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return Self.palette[index % Self.palette.count]
    }
}
