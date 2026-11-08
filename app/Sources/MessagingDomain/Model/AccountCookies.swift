/// The sign-in cookies a client pairs with. Treat like a password: they open the whole account.
public struct AccountCookies: Equatable, Sendable {
    public let values: [String: String]

    public init(values: [String: String]) {
        self.values = values
    }
}
