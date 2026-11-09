#if DEBUG
import Foundation
import MessagingDomain
import MessagingTestSupport

/// Launch-time wiring for UI tests: a scripted client instead of libgm, so the
/// tests drive real screens without a phone or a network.
///
/// Script: sign-in is skipped, pairing shows an emoji, then pairs after a moment and the inbox fills
/// with two conversations. Sending echoes the message back as delivered.
enum UITestLaunch {
    static let argument = "--ui-testing"
    /// Leaves the emoji on screen instead of pairing, so a test can look at it without racing the script.
    static let holdPairingArgument = "--ui-testing-hold-pairing"

    static let signIn = AccountCookies(values: ["SID": "ui-test"])

    static func makeClient() -> FakeMessagingClient {
        let client = FakeMessagingClient()
        client.stubEventsOnStartPairing([.pairingConfirmationEmoji("🦊")])
        client.stubContacts(.success([Contact(name: "Sam Taylor", phoneNumber: "+447700900001", displayNumber: "07700 900001")]))
        client.stubConversation(.success(ConversationID("sam")))
        client.onSendText = { [weak client] text, conversation in
            client?.emit(.messageReceived(Message(
                id: MessageID(UUID().uuidString),
                conversationID: conversation,
                sender: .me,
                sentAt: Date(),
                parts: [.text(text)],
                status: .delivered
            ), isHistorical: false))
        }
        client.onStartPairing = { [weak client] in
            guard let client, !ProcessInfo.processInfo.arguments.contains(holdPairingArgument) else { return }
            Task {
                try? await Task.sleep(for: .seconds(1))
                client.emit(.sessionChanged(SessionData(bytes: Data("ui-test".utf8))))
                client.emit(.paired)
                try? await Task.sleep(for: .milliseconds(300))
                demoInbox.forEach { client.emit(.conversationUpdated($0)) }
                client.emit(.initialSyncCompleted)
            }
        }
        return client
    }

    /// A fake, so the permission prompt can't appear over the window under test.
    static func makePresenter() -> FakeNotificationPresenter {
        FakeNotificationPresenter()
    }

    /// Already set up, so the flows under test go straight to the inbox.
    static func makePhoneWaker() -> FakePhoneWaker {
        FakePhoneWaker()
    }

    static func makeStore() -> InMemorySessionStore {
        InMemorySessionStore()
    }

    private static let demoInbox: [Conversation] = [
        Fixtures.conversation("sam", title: "Sam Taylor", lastActivity: Date(), isUnread: true, preview: "Pub at 7?"),
        Fixtures.conversation("dentist", title: "Dentist", lastActivity: Date(timeIntervalSinceNow: -86_400), preview: "Reminder: Tuesday 9:00"),
    ]
}
#endif
