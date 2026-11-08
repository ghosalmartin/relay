/// RPC identifiers for `gm_call`. Raw values are ABI: they mirror `Method` in
/// Bridge/rpc.go and must never be renumbered.
enum BridgeMethod: Int32, CaseIterable, Sendable {
    case listConversations = 1
    case fetchMessages = 2
    case sendMessage = 3
    case sendReaction = 4
    case markRead = 5
    case listContacts = 6
    case getOrCreateConversation = 7
    case participantThumbnails = 8
    case fullSizeImage = 9
    case deleteMessage = 10
    case getConversation = 11
    case updateConversation = 12
    case downloadMedia = 13
    case uploadMedia = 14
}
