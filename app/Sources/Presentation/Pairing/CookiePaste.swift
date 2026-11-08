import MessagingDomain

/// How sign-in cookies get in from a browser: read the clipboard, make sense of it, and wipe
/// it again, because whatever holds those cookies can open the whole account.
public struct CookiePaste: Sendable {
    let read: @MainActor @Sendable () -> String?
    let clear: @MainActor @Sendable () -> Void
    let parse: @Sendable (String) -> AccountCookies?

    public init(
        read: @escaping @MainActor @Sendable () -> String?,
        clear: @escaping @MainActor @Sendable () -> Void,
        parse: @escaping @Sendable (String) -> AccountCookies?
    ) {
        self.read = read
        self.clear = clear
        self.parse = parse
    }

    /// For tests that never paste.
    public static let unavailable = CookiePaste(read: { nil }, clear: {}, parse: { _ in nil })
}
