/// Someone in the phone's address book. A person with two numbers is two contacts.
public struct Contact: Identifiable, Hashable, Sendable {
    public let name: String
    public let phoneNumber: String
    /// The number as the phone would show it.
    public let displayNumber: String

    public init(name: String, phoneNumber: String, displayNumber: String) {
        self.name = name
        self.phoneNumber = phoneNumber
        self.displayNumber = displayNumber
    }

    public var id: String { phoneNumber }
}
