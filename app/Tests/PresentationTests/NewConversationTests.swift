import MessagingApplication
import MessagingDomain
import MessagingTestSupport
@testable import Presentation
import Testing

private let sam = Contact(name: "Sam Taylor", phoneNumber: "+447700900001", displayNumber: "07700 900001")
private let alex = Contact(name: "alex Jones", phoneNumber: "+447700900002", displayNumber: "07700 900002")

private func loaded(_ query: String = "", contacts: [Contact] = [sam, alex]) -> NewConversationState {
    NewConversationState(contacts: .loaded(contacts), query: query)
}

@Suite struct NewConversationStateTests {
    @Test func contactsAreInAlphabeticalOrderWhateverTheirCase() {
        #expect(loaded().rows.map(\.name) == ["alex Jones", "Sam Taylor"])
    }

    @Test func theSameNumberAppearsOnce() {
        #expect(loaded(contacts: [sam, sam]).rows.count == 1)
    }

    @Test func searchMatchesPartOfAName() {
        #expect(loaded("tay").rows.map(\.id) == [sam.phoneNumber])
    }

    @Test func searchMatchesDigitsHoweverTheyAreSpaced() {
        #expect(loaded("900 001").rows.map(\.id) == [sam.phoneNumber])
    }

    @Test(arguments: [
        ("+44 7700 (900) 123", "+447700900123"),
        ("07700-900.123", "07700900123"),
        ("  12345 ", "12345"),
    ])
    func aTypedNumberIsReducedToItsDigits(query: String, expected: String) {
        #expect(loaded(query).typedNumber == expected)
    }

    @Test(arguments: ["", "12", "sam", "12a45"])
    func otherTextIsNotANumber(query: String) {
        #expect(loaded(query).typedNumber == nil)
    }

    @Test func returnStartsTheOnlyMatch() {
        #expect(loaded("sam").numberForReturnKey == sam.phoneNumber)
    }

    @Test func returnDoesNothingWhenSeveralPeopleMatch() {
        #expect(loaded("a").numberForReturnKey == nil)
    }

    @Test func returnStartsATypedNumberNobodyMatches() {
        #expect(loaded("07911123456").numberForReturnKey == "07911123456")
    }

    @Test func aTypedNumberNeedsNoContactsToHaveLoaded() {
        let state = NewConversationState(contacts: .loading, query: "07911123456")

        #expect(!state.showsLoading)
        #expect(state.numberForReturnKey == "07911123456")
    }
}

@MainActor
@Suite struct NewConversationViewModelTests {
    private func make(_ client: FakeMessagingClient, focus: ConversationFocus = ConversationFocus()) -> NewConversationViewModel {
        NewConversationViewModel(loadContacts: LoadContacts(client: client), startConversation: StartConversation(client: client), focus: focus)
    }

    @Test func runLoadsTheContacts() async {
        let client = FakeMessagingClient()
        client.stubContacts(.success([sam]))
        let viewModel = make(client)

        await viewModel.run()

        #expect(viewModel.state.rows.map(\.name) == ["Sam Taylor"])
    }

    @Test func aFailedLoadCanBeRetried() async {
        let client = FakeMessagingClient()
        client.stubContacts(.failure(.phoneUnreachable))
        let viewModel = make(client)
        await viewModel.run()
        #expect(viewModel.state.loadFailure != nil)

        client.stubContacts(.success([sam]))
        await viewModel.send(.retryTapped).value

        #expect(viewModel.state.loadFailure == nil)
        #expect(viewModel.state.rows.count == 1)
    }

    @Test func choosingSomeoneAsksTheInboxToOpenTheirConversationAndFinishes() async {
        let client = FakeMessagingClient()
        client.stubConversation(.success(ConversationID("sam")))
        let focus = ConversationFocus()
        let viewModel = make(client, focus: focus)

        await viewModel.send(.numberChosen(sam.phoneNumber)).value

        #expect(client.calls == [.conversation(withPhoneNumber: sam.phoneNumber)])
        #expect(focus.openRequest.value == ConversationID("sam"))
        #expect(viewModel.state.isFinished)
    }

    @Test func aFailureStaysOnTheScreenAndExplains() async {
        let client = FakeMessagingClient()
        client.stubConversation(.failure(.phoneUnreachable))
        let focus = ConversationFocus()
        let viewModel = make(client, focus: focus)

        await viewModel.send(.numberChosen(sam.phoneNumber)).value

        #expect(viewModel.state.startError?.contains("isn't responding") == true)
        #expect(!viewModel.state.isFinished)
        #expect(!viewModel.state.isStarting)
        #expect(focus.openRequest.value == nil)
    }

    @Test func returnWithNothingToStartAsksNothing() async {
        let client = FakeMessagingClient()
        let viewModel = make(client)

        await viewModel.send(.returnPressed).value

        #expect(client.calls.isEmpty)
    }
}
