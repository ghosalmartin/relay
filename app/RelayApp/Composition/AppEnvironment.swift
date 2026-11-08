import Foundation
import KeychainAdapter
import LibGMAdapter
import MessagingApplication
import MessagingDomain
import Presentation

/// The composition root: the one place that chooses concrete adapters and builds
/// view models. Nothing else in the app constructs a client or a store.
@MainActor
final class AppEnvironment {
    private let client: any MessagingClient
    private let store: any SessionStore

    init(client: any MessagingClient, store: any SessionStore) {
        self.client = client
        self.store = store
    }

    /// libgm and the Keychain normally; a scripted client under UI tests.
    static func forCurrentLaunch() -> AppEnvironment {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(UITestLaunch.argument) {
            return AppEnvironment(client: UITestLaunch.makeClient(), store: UITestLaunch.makeStore())
        }
        #endif
        return AppEnvironment(
            client: LibGMMessagingClient.live(),
            store: KeychainSessionStore(service: "dev.featurenotabug.relay")
        )
    }

    func makeRootViewModel() -> RootViewModel {
        RootViewModel(
            startSession: StartSession(client: client, store: store),
            persistSessionChanges: PersistSessionChanges(client: client, store: store),
            observeConnectionStatus: ObserveConnectionStatus(client: client),
            unpair: Unpair(client: client, store: store)
        )
    }

    func makePairingViewModel(onPaired: @escaping @MainActor () -> Void) -> PairingViewModel {
        PairingViewModel(pairDevice: PairDevice(client: client), onPaired: onPaired)
    }

    func makeInboxViewModel() -> InboxViewModel {
        InboxViewModel(
            observeInbox: ObserveInbox(client: client),
            observeConnectionStatus: ObserveConnectionStatus(client: client)
        )
    }

    func makeThreadViewModel(for conversation: Conversation) -> ThreadViewModel {
        ThreadViewModel(
            conversation: conversation,
            loadHistory: LoadThreadHistory(client: client),
            observeThread: ObserveThread(client: client),
            sendText: SendText(client: client),
            markRead: MarkConversationRead(client: client)
        )
    }
}
