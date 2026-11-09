import MessagingApplication
import MessagingDomain
import Observation

@MainActor @Observable
public final class NewConversationViewModel {
    public private(set) var state = NewConversationState()

    private let loadContacts: LoadContacts
    private let startConversation: StartConversation
    private let focus: ConversationFocus

    public init(loadContacts: LoadContacts, startConversation: StartConversation, focus: ConversationFocus) {
        self.loadContacts = loadContacts
        self.startConversation = startConversation
        self.focus = focus
    }

    /// Fetches the address book. Call from the view's `.task`.
    public func run() async {
        await load()
    }

    @discardableResult
    public func send(_ intent: NewConversationIntent) -> Task<Void, Never> {
        switch intent {
        case .queryChanged(let text):
            apply(.queryChanged(text))
        case .errorDismissed:
            apply(.errorDismissed)
        case .numberChosen(let number):
            return Task { await start(number) }
        case .returnPressed:
            guard let number = state.numberForReturnKey else { break }
            return Task { await start(number) }
        case .retryTapped:
            return Task { await load() }
        }
        return Task {}
    }

    private func load() async {
        apply(.contactsLoading)
        do {
            apply(.contactsLoaded(try await loadContacts()))
        } catch {
            apply(.contactsFailed(ThreadViewModel.describe(error)))
        }
    }

    private func start(_ number: String) async {
        guard !state.isStarting else { return }
        apply(.starting)
        do {
            // The inbox opens it, waiting if the conversation hasn't reached it yet.
            focus.requestOpen(try await startConversation(with: number))
            apply(.started)
        } catch {
            apply(.startFailed(ThreadViewModel.describe(error)))
        }
    }

    private func apply(_ mutation: NewConversationMutation) {
        state = NewConversationReducer.reduce(state, mutation)
    }
}
