import LibGMKit
import MessagingDomain

/// Packs libgm's history cursor into the domain's opaque token and back.
enum CursorCodec {
    private static let separator: Character = "|"

    static func token(from cursor: GM.Cursor) -> HistoryCursor? {
        guard !cursor.lastItemID.isEmpty else { return nil }
        return HistoryCursor(token: "\(cursor.lastItemTimestamp)\(separator)\(cursor.lastItemID)")
    }

    static func cursor(from token: HistoryCursor) -> GM.Cursor? {
        let pieces = token.token.split(separator: separator, maxSplits: 1)
        guard pieces.count == 2, let timestamp = Int64(pieces[0]) else { return nil }
        return GM.Cursor.with {
            $0.lastItemTimestamp = timestamp
            $0.lastItemID = String(pieces[1])
        }
    }
}
