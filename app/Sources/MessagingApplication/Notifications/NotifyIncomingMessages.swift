import MessagingDomain

/// Alerts the user about new messages they can't already see, and clears those alerts
/// once they look at the conversation. Start it once, in a task that lives as long as the app.
public struct NotifyIncomingMessages: Sendable {
    private let events: AsyncStream<MessagingEvent>
    private let presenter: any NotificationPresenter
    private let focus: ConversationFocus
    private let avatars: AvatarBook

    /// Subscribes straight away, so build this before anything can connect.
    public init(client: any MessagingClient, presenter: any NotificationPresenter, focus: ConversationFocus, avatars: AvatarBook = AvatarBook()) {
        events = client.events()
        self.presenter = presenter
        self.focus = focus
        self.avatars = avatars
    }

    public func callAsFunction() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await announceMessages() }
            group.addTask { await clearAlertsWhenViewed() }
        }
    }

    private func announceMessages() async {
        _ = await events.reduce(NotificationDecider()) { decider, event in
            let decision = decider.deciding(event, visible: focus.attention.value.visibleConversation)
            // Asked here, not at launch, so the prompt appears once there's something to notify about.
            if !decider.inbox.hasCompletedInitialSync, decision.next.inbox.hasCompletedInitialSync {
                await presenter.requestAuthorization()
            }
            if let notification = decision.notification {
                await presenter.present(notification.withSenderPhoto(decision.sender.flatMap(avatars.photo)))
            }
            return decision.next
        }
    }

    private func clearAlertsWhenViewed() async {
        for await attention in focus.attention.values() {
            if let conversation = attention.visibleConversation {
                await presenter.dismissNotifications(in: conversation)
            }
        }
    }
}
