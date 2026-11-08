import Foundation
import MessagingDomain
import OSLog
@preconcurrency import UserNotifications

/// Shows message alerts through macOS Notification Centre and reports clicks on them.
public final class SystemNotificationPresenter: NSObject, NotificationPresenter, UNUserNotificationCenterDelegate, Sendable {
    private static let conversationKey = "conversationID"
    private static let log = Logger(subsystem: "dev.featurenotabug.Relay", category: "notifications")

    private let onOpen: @Sendable (ConversationID) -> Void

    /// - Parameter onOpen: called with the conversation when the user clicks an alert.
    public init(onOpen: @escaping @Sendable (ConversationID) -> Void) {
        self.onOpen = onOpen
        super.init()
    }

    /// Must be called before the app finishes launching, or a click that launched the app is lost.
    /// Kept out of `init` because the notification centre aborts in a process with no app bundle.
    public func becomeCenterDelegate() {
        center.delegate = self
    }

    private var center: UNUserNotificationCenter { .current() }

    // MARK: NotificationPresenter

    public func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Self.log.error("Notification permission failed: \(error, privacy: .public)")
        }
    }

    public func present(_ notification: MessageNotification) async {
        let request = UNNotificationRequest(
            identifier: notification.messageID.rawValue,
            content: Self.content(for: notification),
            trigger: nil
        )
        do {
            try await center.add(request)
        } catch {
            Self.log.error("Couldn't show notification: \(error, privacy: .public)")
        }
    }

    public func dismissNotifications(in conversation: ConversationID) async {
        let delivered = await center.deliveredNotifications()
        let identifiers = delivered
            .filter { $0.request.content.threadIdentifier == conversation.rawValue }
            .map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    // MARK: Mapping

    static func content(for notification: MessageNotification) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.threadIdentifier = notification.conversationID.rawValue   // groups alerts by conversation
        content.userInfo = [conversationKey: notification.conversationID.rawValue]
        return content
    }

    static func conversationID(from userInfo: [AnyHashable: Any]) -> ConversationID? {
        (userInfo[conversationKey] as? String).map(ConversationID.init)
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Without this, macOS hides alerts while the app is frontmost, even for a different
    /// conversation from the one on screen. `NotifyIncomingMessages` has already filtered those.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if let conversation = Self.conversationID(from: response.notification.request.content.userInfo) {
            onOpen(conversation)
        }
    }
}
