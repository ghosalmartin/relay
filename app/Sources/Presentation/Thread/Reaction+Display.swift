import MessagingDomain

public extension Reaction {
    /// The count only appears once more than one person has used the emoji.
    var displayText: String {
        count > 1 ? "\(emoji) \(count)" : emoji
    }
}
