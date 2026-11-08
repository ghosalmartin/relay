#if DEBUG
import Foundation
import MessagingDomain
import MessagingTestSupport

/// Launch-time wiring for UI tests: a scripted client instead of libgm, so the
/// tests drive real screens without a phone or a network.
///
/// Script: pairing shows a QR code, then pairs after a moment and the inbox fills
/// with two conversations. Sending echoes the message back as delivered.
enum UITestLaunch {
    static let argument = "--ui-testing"

    static func makeClient() -> FakeMessagingClient {
        let client = FakeMessagingClient()
        client.stubEventsOnStartPairing([.pairingCode("relay-ui-test-qr")])
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
            guard let client else { return }
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

    static func makeStore() -> InMemorySessionStore {
        InMemorySessionStore()
    }

    private static let demoInbox: [Conversation] = [
        Fixtures.conversation("sam", title: "Sam Taylor", lastActivity: Date(), isUnread: true, preview: "Pub at 7?"),
        Fixtures.conversation("dentist", title: "Dentist", lastActivity: Date(timeIntervalSinceNow: -86_400), preview: "Reminder: Tuesday 9:00"),
    ]
}
#endif
