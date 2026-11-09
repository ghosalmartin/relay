import MessagingApplication
import MessagingDomain
import Observation

@MainActor @Observable
public final class InboxViewModel {
    public private(set) var state = InboxState()

    private let observeInbox: ObserveInbox
    private let observeConnectionStatus: ObserveConnectionStatus
    private let focus: ConversationFocus
    private let loadAvatars: LoadAvatars
    private let archive: ArchiveConversation
    private let delete: DeleteConversation
    private let mute: MuteConversation

    public init(
        observeInbox: ObserveInbox,
        observeConnectionStatus: ObserveConnectionStatus,
        focus: ConversationFocus,
        loadAvatars: LoadAvatars,
        archive: ArchiveConversation,
        delete: DeleteConversation,
        mute: MuteConversation
    ) {
        self.archive = archive
        self.delete = delete
        self.mute = mute
        self.observeInbox = observeInbox
        self.observeConnectionStatus = observeConnectionStatus
        self.focus = focus
        self.loadAvatars = loadAvatars
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

    @discardableResult
    public func send(_ intent: InboxIntent) -> Task<Void, Never> {
        switch intent {
        case .selected(let id): apply(.selected(id))
        case .searchChanged(let text): apply(.searchChanged(text))
        case .shortcutPressed(let position):
            if let id = state.conversationID(atShortcut: position) { apply(.selected(id)) }
        case .composeTapped: apply(.composingChanged(true))
        case .composeDismissed: apply(.composingChanged(false))
        case .deleteTapped(let id): apply(.deleteRequested(id))
        case .deleteCancelled: apply(.deleteRequested(nil))
        case .actionErrorDismissed: apply(.actionFailed(nil))
        case .archiveTapped(let id):
            return perform { [archive] () throws(MessagingError) in try await archive(id) }
        case .muteTapped(let id, let isMuted):
            return perform { [mute] () throws(MessagingError) in try await mute(id, isMuted: isMuted) }
        case .deleteConfirmed:
            guard let id = state.confirmingDelete else { break }
            apply(.deleteRequested(nil))
            return perform { [delete] () throws(MessagingError) in try await delete(id) }
        }
        return Task {}
    }

    private func perform(_ action: @escaping @Sendable () async throws(MessagingError) -> Void) -> Task<Void, Never> {
        Task {
            do {
                try await action()
            } catch {
                apply(.actionFailed(ThreadViewModel.describe(error)))
            }
        }
    }

    private func followInbox() async {
        // Photos load alongside, because a slow phone mustn't hold up inbox changes.
        await withDiscardingTaskGroup { group in
            for await snapshot in observeInbox() {
                apply(.inboxChanged(snapshot))
                let missing = state.avatarsToLoad
                guard !missing.isEmpty else { continue }
                apply(.avatarsRequested(missing))
                group.addTask { await self.fetchAvatars(missing) }
            }
        }
    }

    private func fetchAvatars(_ participants: Set<ParticipantID>) async {
        do {
            apply(.avatarsLoaded(try await loadAvatars(participants)))
        } catch {
            apply(.avatarsFailed(participants))
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
