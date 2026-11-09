import MessagingDomain

/// What can be done to a message from its context menu.
struct MessageActions {
    let reply: (MessageID) -> Void
    let react: (String, MessageID) -> Void
    let delete: (MessageID) -> Void
    let openFile: (Attachment) -> Void
}
