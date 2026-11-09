import Foundation
import MessagingDomain

public struct NewConversationState: Equatable, Sendable {
    public enum Contacts: Equatable, Sendable {
        case loading
        case loaded([Contact])
        case failed(message: String)
    }

    public let contacts: Contacts
    public let query: String
    public let isStarting: Bool
    public let startError: String?
    public let isFinished: Bool

    public init(
        contacts: Contacts = .loading,
        query: String = "",
        isStarting: Bool = false,
        startError: String? = nil,
        isFinished: Bool = false
    ) {
        self.contacts = contacts
        self.query = query
        self.isStarting = isStarting
        self.startError = startError
        self.isFinished = isFinished
    }

    /// A copy with the given fields replaced. For an optional field, `.some(nil)` clears it and omitting it keeps it.
    func with(
        contacts: Contacts? = nil,
        query: String? = nil,
        isStarting: Bool? = nil,
        startError: String?? = nil,
        isFinished: Bool? = nil
    ) -> NewConversationState {
        NewConversationState(
            contacts: contacts ?? self.contacts,
            query: query ?? self.query,
            isStarting: isStarting ?? self.isStarting,
            startError: startError ?? self.startError,
            isFinished: isFinished ?? self.isFinished
        )
    }

    /// Contacts matching the query by name or digits, A to Z, each number once.
    public var rows: [ContactRow] {
        guard case .loaded(let contacts) = contacts else { return [] }
        return Dictionary(contacts.map { ($0.phoneNumber, $0) }, uniquingKeysWith: { first, _ in first })
            .values
            .filter(matchesQuery)
            .sorted { ($0.name.localizedLowercase, $0.phoneNumber) < ($1.name.localizedLowercase, $1.phoneNumber) }
            .map(ContactRow.init)
    }

    /// What the query means as a phone number, in the form the phone expects. Nil if it isn't one.
    public var typedNumber: String? {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.unicodeScalars.allSatisfy(Self.phoneNumberCharacters.contains) else { return nil }
        let digits = text.filter(\.isNumber)
        guard digits.count >= Self.shortestNumber else { return nil }
        return (text.hasPrefix("+") ? "+" : "") + digits
    }

    /// What Return starts: the only match, otherwise a number that was typed in.
    public var numberForReturnKey: String? {
        rows.count == 1 ? rows[0].id : typedNumber
    }

    public var showsLoading: Bool { contacts == .loading && typedNumber == nil }

    public var loadFailure: String? {
        guard case .failed(let message) = contacts else { return nil }
        return message
    }

    private func matchesQuery(_ contact: Contact) -> Bool {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return true }
        let digits = text.filter(\.isNumber)
        return contact.name.localizedCaseInsensitiveContains(text)
            || (!digits.isEmpty && contact.phoneNumber.filter(\.isNumber).contains(digits))
    }

    private static let phoneNumberCharacters = CharacterSet(charactersIn: "+0123456789 ()-.")
    /// Short enough for the service numbers that banks and couriers text from.
    private static let shortestNumber = 3
}

/// One person to pick, already worded for display.
public struct ContactRow: Identifiable, Equatable, Sendable {
    /// The number to message.
    public let id: String
    public let name: String
    public let number: String
    public let initials: String

    init(_ contact: Contact) {
        id = contact.phoneNumber
        name = contact.name
        number = contact.displayNumber
        initials = ConversationRow.initials(of: contact.name)
    }
}

public enum NewConversationIntent: Equatable, Sendable {
    case queryChanged(String)
    case numberChosen(String)
    case returnPressed
    case retryTapped
    case errorDismissed
}

public enum NewConversationMutation: Equatable, Sendable {
    case contactsLoading
    case contactsLoaded([Contact])
    case contactsFailed(String)
    case queryChanged(String)
    case starting
    case started
    case startFailed(String)
    case errorDismissed
}
