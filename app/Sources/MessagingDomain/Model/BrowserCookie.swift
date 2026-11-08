/// One cookie as a browser reports it.
public struct BrowserCookie: Equatable, Sendable {
    public let name: String
    public let domain: String
    public let value: String

    public init(name: String, domain: String, value: String) {
        self.name = name
        self.domain = domain
        self.value = value
    }
}
