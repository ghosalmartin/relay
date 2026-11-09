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

    static func data(for emoji: String) -> GM.ReactionData {
        .with {
            $0.unicode = emoji
            $0.type = type(of: emoji)
        }
    }

    private static func type(of emoji: String) -> Conversations_EmojiType {
        switch emoji {
        case "👍": .like
        case "😍": .love
        case "😂": .laugh
        case "😮": .surprised
        case "😥": .sad
        case "😠": .angry
        case "👎": .dislike
        case "🤔": .questioning
        case "😢": .cryingFace
        case "😡": .poutingFace
        case "❤️": .redHeart
        default: .custom
        }
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
