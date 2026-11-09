import Foundation
import MessagingDomain
import OSLog
@preconcurrency import UserNotifications

/// Shows message alerts through macOS Notification Centre and reports clicks on them.
public final class SystemNotificationPresenter: NSObject, NotificationPresenter, UNUserNotificationCenterDelegate, Sendable {
    private static let conversationKey = "conversationID"
    private static let messageCategory = "message"
    private static let replyAction = "reply"
    private static let log = Logger(subsystem: "dev.featurenotabug.Relay", category: "notifications")

    private let onOpen: @Sendable (ConversationID) -> Void
    private let onReply: @Sendable (ConversationID, String) -> Void

    /// - Parameters:
    ///   - onOpen: called with the conversation when the user clicks an alert.
    ///   - onReply: called with what the user typed into an alert's Reply field.
    public init(
        onOpen: @escaping @Sendable (ConversationID) -> Void,
        onReply: @escaping @Sendable (ConversationID, String) -> Void = { _, _ in }
    ) {
        self.onOpen = onOpen
        self.onReply = onReply
        super.init()
    }

    /// Must be called before the app finishes launching, or a click that launched the app is lost.
    /// Kept out of `init` because the notification centre aborts in a process with no app bundle.
    public func becomeCenterDelegate() {
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.messageCategory,
                actions: [UNTextInputNotificationAction(
                    identifier: Self.replyAction,
                    title: "Reply",
                    options: [],
                    textInputButtonTitle: "Send",
                    textInputPlaceholder: "Text Message"
                )],
                intentIdentifiers: []
            ),
        ])
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
        content.categoryIdentifier = messageCategory      // what puts Reply on the alert
        content.threadIdentifier = notification.conversationID.rawValue   // groups alerts by conversation
        content.userInfo = [conversationKey: notification.conversationID.rawValue]
        content.attachments = photoAttachment(for: notification).map { [$0] } ?? []
        return content
    }

    /// A photo that can't be attached shouldn't cost the user the alert.
    private static func photoAttachment(for notification: MessageNotification) -> UNNotificationAttachment? {
        guard let photo = notification.senderPhoto else { return nil }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension(of: photo))
        do {
            try photo.write(to: file)
            return try UNNotificationAttachment(identifier: "sender-photo", url: file)
        } catch {
            log.error("Couldn't attach photo: \(error, privacy: .public)")
            return nil
        }
    }

    /// Notification Centre goes by the extension, and libgm doesn't say which format a thumbnail is in.
    static func fileExtension(of photo: Data) -> String {
        photo.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "png" : "jpg"
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
        guard let conversation = Self.conversationID(from: response.notification.request.content.userInfo) else { return }
        if let reply = response as? UNTextInputNotificationResponse {
            onReply(conversation, reply.userText)
        } else {
            onOpen(conversation)
        }
    }
}
