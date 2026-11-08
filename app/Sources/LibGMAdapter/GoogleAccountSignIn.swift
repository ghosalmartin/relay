import Foundation
import MessagingDomain

/// What libgm's Google account pairing needs from a web sign-in. Google has discontinued QR
/// pairing, so this is the only way in.
public enum GoogleAccountSignIn {
    public static let startURL = URL(string: "https://accounts.google.com/AccountChooser?continue=https://messages.google.com/web/config")!
    /// Sign-in has finished once the browser lands here.
    public static let completionHost = "messages.google.com"
    /// Google refuses sign-in from pages that don't identify as a full browser.
    public static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    private static let requiredCookies = ["OSID": "messages.google.com", "SID": "google.com", "HSID": "google.com",
                                          "SSID": "google.com", "APISID": "google.com", "SAPISID": "google.com"]
    private static let optionalCookies = ["__Secure-1PSIDTS": "google.com"]

    /// The cookies to pair with, or nil until every required one is present.
    public static func cookies(from browserCookies: [BrowserCookie]) -> AccountCookies? {
        let wanted = requiredCookies.merging(optionalCookies) { first, _ in first }
        let found = Dictionary(
            browserCookies
                .filter { wanted[$0.name] == bareDomain($0.domain) }
                .map { ($0.name, $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        return requiredCookies.keys.allSatisfy(found.keys.contains) ? AccountCookies(values: found) : nil
    }

    /// The cookies in a "Copy as cURL" command from Chrome's DevTools, or nil if any required one is missing.
    /// A cookie header carries no domains, so this relies on it coming from a messages.google.com request.
    public static func cookies(fromCurl command: String) -> AccountCookies? {
        guard let header = cookieHeader(in: command) else { return nil }
        let found = Dictionary(
            header.split(separator: ";").compactMap(nameAndValue).filter { isWanted($0.0) },
            uniquingKeysWith: { first, _ in first }
        )
        return requiredCookies.keys.allSatisfy(found.keys.contains) ? AccountCookies(values: found) : nil
    }

    private static func cookieHeader(in command: String) -> String? {
        // Chrome switches to $'...' quoting when a value holds a character such as "!".
        if let match = command.firstMatch(of: /(?:^|\s)(?:-b|--cookie)\s+\$?'([^']*)'/) { return String(match.1) }
        if let match = command.firstMatch(of: /(?i)-H\s+\$?'cookie:\s*([^']*)'/) { return String(match.1) }
        return nil
    }

    private static func nameAndValue(_ part: Substring) -> (String, String)? {
        let trimmed = part.trimmingCharacters(in: .whitespaces)
        guard let separator = trimmed.firstIndex(of: "=") else { return nil }
        return (String(trimmed[..<separator]), String(trimmed[trimmed.index(after: separator)...]))
    }

    private static func isWanted(_ name: String) -> Bool {
        requiredCookies[name] != nil || optionalCookies[name] != nil
    }

    private static func bareDomain(_ domain: String) -> String {
        domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
    }
}
