import MessagingApplication
import Observation

@MainActor @Observable
public final class InboxViewModel {
    public private(set) var state = InboxState()

    private let observeInbox: ObserveInbox
    private let observeConnectionStatus: ObserveConnectionStatus

    public init(observeInbox: ObserveInbox, observeConnectionStatus: ObserveConnectionStatus) {
        self.observeInbox = observeInbox
        self.observeConnectionStatus = observeConnectionStatus
    }

    /// Keeps the inbox live until the view goes away. Call from the view's `.task`.
    public func run() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.followInbox() }
            group.addTask { await self.followConnection() }
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

    private func apply(_ mutation: InboxMutation) {
        state = InboxReducer.reduce(state, mutation)
    }
}
