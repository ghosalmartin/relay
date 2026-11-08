/// Where the session credentials live between launches (the Keychain, in the app).
public protocol SessionStore: Sendable {
    func load() async throws -> SessionData?
    func save(_ session: SessionData) async throws
    func clear() async throws
}
