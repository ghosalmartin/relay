import MessagingApplication
import Observation

@MainActor @Observable
public final class InboxViewModel {
    public private(set) var state = InboxState()

    private let observeInbox: ObserveInbox
    private let observeConnectionStatus: ObserveConnectionStatus
    private let focus: ConversationFocus

    public init(observeInbox: ObserveInbox, observeConnectionStatus: ObserveConnectionStatus, focus: ConversationFocus) {
        self.observeInbox = observeInbox
        self.observeConnectionStatus = observeConnectionStatus
        self.focus = focus
    }

    /// Keeps the inbox live until the view goes away. Call from the view's `.task`.
    public func run() async {
        focus.select(state.selection)
        defer { focus.select(nil) }     // the window has gone, so nothing is on screen
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.followInbox() }
            group.addTask { await self.followConnection() }
            group.addTask { await self.followOpenRequests() }
        }
    }

    public func send(_ intent: InboxIntent) {
        switch intent {
        case .selected(let id): apply(.selected(id))
        case .searchChanged(let text): apply(.searchChanged(text))
        }
    }

    private func followInbox() async {
        for await snapshot in observeInbox() {
            apply(.inboxChanged(snapshot))
        }
    }

    private func followConnection() async {
        for await status in observeConnectionStatus() {
            apply(.connectionChanged(status))
        }
    }

    private func followOpenRequests() async {
        for await request in focus.openRequest.values() {
            guard let request else { continue }
            apply(.openRequested(request))
            focus.openRequest.set(nil)
        }
    }

    private func apply(_ mutation: InboxMutation) {
        state = InboxReducer.reduce(state, mutation)
        focus.select(state.selection)
    }
}
