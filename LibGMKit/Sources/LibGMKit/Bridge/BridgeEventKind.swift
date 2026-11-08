/// Event kinds sent by the Go bridge. Raw values are ABI: they mirror `EventKind` in
/// Bridge/events.go and must never be renumbered.
enum BridgeEventKind: Int32, CaseIterable, Sendable {
    case qrCode = 1
    case paired = 2
    case sessionUpdated = 3
    case initialSyncDone = 4
    case conversation = 5
    case message = 6
    case historicalMessage = 7
    case typing = 8
    case settings = 9
    case phoneUnreachable = 10
    case phoneReachable = 11
    case fatalError = 12
    case transientError = 13
    case connectionRecovered = 14
    case loggedOut = 15
    case googleAccountEmoji = 16
}
