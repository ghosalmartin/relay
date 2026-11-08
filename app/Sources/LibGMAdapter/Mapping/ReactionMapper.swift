import LibGMKit
import MessagingDomain

/// Google Messages reaction → domain `Reaction`.
enum ReactionMapper {
    /// Nil when nobody is left on it, or it's a custom sticker with no emoji to show.
    static func reaction(from entry: GM.ReactionEntry) -> Reaction? {
        let shown = emoji(for: entry.data)
        guard !shown.isEmpty, !entry.participantIds.isEmpty else { return nil }
        return Reaction(emoji: shown, count: entry.participantIds.count)
    }

    /// Standard reactions are sent as a type rather than as the emoji itself.
    private static func emoji(for data: GM.ReactionData) -> String {
        switch data.type {
        case .like: "👍"
        case .love: "😍"
        case .laugh: "😂"
        case .surprised: "😮"
        case .sad: "😥"
        case .angry: "😠"
        case .dislike: "👎"
        case .questioning: "🤔"
        case .cryingFace: "😢"
        case .poutingFace: "😡"
        case .redHeart: "❤️"
        default: data.unicode
        }
    }
}
