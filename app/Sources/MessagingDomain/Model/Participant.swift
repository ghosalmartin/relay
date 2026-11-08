/// Someone taking part in a conversation.
public struct Participant: Identifiable, Hashable, Sendable {
    public let id: ParticipantID
    public let displayName: String
    public let phoneNumber: String?
    public let isMe: Bool

    public init(id: ParticipantID, displayName: String, phoneNumber: String?, isMe: Bool) {
        self.id = id
        self.displayName = displayName
        self.phoneNumber = phoneNumber
        self.isMe = isMe
    }
}
