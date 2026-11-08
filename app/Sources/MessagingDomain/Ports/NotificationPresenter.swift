/// Shows alerts outside the app's window. Failures are not reported: a missed alert
/// (permission denied, Focus mode) must never get in the way of messaging.
public protocol NotificationPresenter: Sendable {
    func requestAuthorization() async
    func present(_ notification: MessageNotification) async
    /// Removes alerts for a conversation the user is now looking at.
    func dismissNotifications(in conversation: ConversationID) async
}
