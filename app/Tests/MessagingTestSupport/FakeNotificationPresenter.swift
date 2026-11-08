import MessagingDomain
import Synchronization

/// Records what would have been shown, so tests and UI-test launches never touch Notification Centre.
public final class FakeNotificationPresenter: NotificationPresenter {
    private struct Log {
        var authorizationRequests = 0
        var presented: [MessageNotification] = []
        var dismissed: [ConversationID] = []
    }

    private let log = Mutex(Log())

    public init() {}

    public var authorizationRequests: Int { log.withLock { $0.authorizationRequests } }
    public var presented: [MessageNotification] { log.withLock { $0.presented } }
    public var dismissed: [ConversationID] { log.withLock { $0.dismissed } }

    public func requestAuthorization() async { log.withLock { $0.authorizationRequests += 1 } }
    public func present(_ notification: MessageNotification) async { log.withLock { $0.presented.append(notification) } }
    public func dismissNotifications(in conversation: ConversationID) async { log.withLock { $0.dismissed.append(conversation) } }
}
