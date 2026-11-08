import AppKit
import Foundation
import KeychainAdapter
import LibGMAdapter
import MessagingApplication
import MessagingDomain
import Presentation
import UserNotificationsAdapter

/// The composition root: the one place that chooses concrete adapters and builds
/// view models. Nothing else in the app constructs a client or a store.
@MainActor
final class AppEnvironment {
    let rootViewModel: RootViewModel
    let windowOpener: MainWindowOpener

    private let client: any MessagingClient
    private let session: LiveSession
    private let focus: ConversationFocus
    private let notifyIncomingMessages: NotifyIncomingMessages

    /// Everything that listens to the client is built here, before `start()` can connect it,
    /// so none of them can miss the burst of events that follows.
    init(
        client: any MessagingClient,
        store: any SessionStore,
        presenter: any NotificationPresenter,
        focus: ConversationFocus,
        windowOpener: MainWindowOpener
    ) {
        let session = LiveSession(client: client)
        self.client = client
        self.session = session
        self.focus = focus
        self.windowOpener = windowOpener
        notifyIncomingMessages = NotifyIncomingMessages(client: client, presenter: presenter, focus: focus)
        rootViewModel = RootViewModel(
            startSession: StartSession(client: client, store: store),
            persistSessionChanges: PersistSessionChanges(client: client, store: store),
            observeConnectionStatus: ObserveConnectionStatus(session: session),
            unpair: Unpair(client: client, store: store)
        )
    }

    /// libgm and the Keychain normally; a scripted client under UI tests.
    static func forCurrentLaunch() -> AppEnvironment {
        let focus = ConversationFocus()
        let windowOpener = MainWindowOpener()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(UITestLaunch.argument) {
            return AppEnvironment(
                client: UITestLaunch.makeClient(),
                store: UITestLaunch.makeStore(),
                presenter: UITestLaunch.makePresenter(),
                focus: focus,
                windowOpener: windowOpener
            )
        }
        #endif
        let presenter = SystemNotificationPresenter { conversation in
            focus.requestOpen(conversation)
            Task { @MainActor in windowOpener.bringToFront() }
        }
        presenter.becomeCenterDelegate()
        return AppEnvironment(
            client: LibGMMessagingClient.live(),
            store: KeychainSessionStore(service: "dev.featurenotabug.relay"),
            presenter: presenter,
            focus: focus,
            windowOpener: windowOpener
        )
    }

    /// Runs the session for the life of the app. Separate from any window, so closing one changes nothing.
    /// Call once.
    func start() {
        let session = session
        let notifyIncomingMessages = notifyIncomingMessages
        let rootViewModel = rootViewModel
        Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await session.run() }
                group.addTask { await notifyIncomingMessages() }
                group.addTask { await rootViewModel.run() }
            }
        }
    }

    func setAppActive(_ isActive: Bool) {
        focus.setAppActive(isActive)
    }

    func makePairingViewModel(onPaired: @escaping @MainActor () -> Void) -> PairingViewModel {
        PairingViewModel(pairDevice: PairDevice(client: client), onPaired: onPaired)
    }

    func makeInboxViewModel() -> InboxViewModel {
        InboxViewModel(
            observeInbox: ObserveInbox(session: session),
            observeConnectionStatus: ObserveConnectionStatus(session: session),
            focus: focus
        )
    }

    func makeThreadViewModel(for conversation: Conversation) -> ThreadViewModel {
        ThreadViewModel(
            conversation: conversation,
            loadHistory: LoadThreadHistory(client: client),
            observeThread: ObserveThread(client: client),
            sendText: SendText(client: client),
            markRead: MarkConversationRead(client: client),
            focus: focus
        )
    }
}
