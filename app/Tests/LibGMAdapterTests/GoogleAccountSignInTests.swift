@testable import LibGMAdapter
import MessagingDomain
import Testing

@Suite struct GoogleAccountSignInTests {
    private let complete = [
        BrowserCookie(name: "OSID", domain: "messages.google.com", value: "osid"),
        BrowserCookie(name: "SID", domain: ".google.com", value: "sid"),
        BrowserCookie(name: "HSID", domain: ".google.com", value: "hsid"),
        BrowserCookie(name: "SSID", domain: ".google.com", value: "ssid"),
        BrowserCookie(name: "APISID", domain: ".google.com", value: "apisid"),
        BrowserCookie(name: "SAPISID", domain: ".google.com", value: "sapisid"),
    ]

    @Test func collectsTheRequiredCookies() {
        #expect(GoogleAccountSignIn.cookies(from: complete)?.values["OSID"] == "osid")
        #expect(GoogleAccountSignIn.cookies(from: complete)?.values.count == 6)
    }

    @Test func waitsUntilEveryRequiredCookieIsThere() {
        #expect(GoogleAccountSignIn.cookies(from: Array(complete.dropFirst())) == nil)
    }

    @Test func takesACookieOnlyFromItsOwnDomain() {
        let otherOSID = BrowserCookie(name: "OSID", domain: "myaccount.google.com", value: "wrong")

        #expect(GoogleAccountSignIn.cookies(from: [otherOSID] + complete)?.values["OSID"] == "osid")
        #expect(GoogleAccountSignIn.cookies(from: [otherOSID] + complete.dropFirst()) == nil)
    }

    @Test func leavesOutCookiesItDoesNotNeed() {
        let extra = BrowserCookie(name: "NID", domain: ".google.com", value: "tracking")

        #expect(GoogleAccountSignIn.cookies(from: complete + [extra])?.values["NID"] == nil)
    }

    private let curlCookies = "OSID=osid; SID=sid; HSID=hsid; SSID=ssid; APISID=apisid; SAPISID=sap=isid; NID=tracking"

    @Test func readsTheCookiesFromChromesCurlCommand() {
        let command = "curl 'https://messages.google.com/web/config' \\\n  -H 'accept: */*' \\\n  -b '\(curlCookies)' \\\n  -H 'user-agent: Chrome'"

        let cookies = GoogleAccountSignIn.cookies(fromCurl: command)

        #expect(cookies?.values.count == 6)
        #expect(cookies?.values["SAPISID"] == "sap=isid")     // only the first = separates name from value
        #expect(cookies?.values["NID"] == nil)
    }

    @Test func alsoReadsACookieHeader() {
        let command = "curl 'https://messages.google.com/web/config' -H 'Cookie: \(curlCookies)'"

        #expect(GoogleAccountSignIn.cookies(fromCurl: command)?.values["OSID"] == "osid")
    }

    @Test(arguments: ["-b $'", "--cookie $'", "-H $'cookie: "])
    func readsChromesAlternativeQuoting(flag: String) {
        let command = "curl 'https://messages.google.com/web/config' \(flag)\(curlCookies); OTHER=a\\u0021b'"

        #expect(GoogleAccountSignIn.cookies(fromCurl: command)?.values["OSID"] == "osid")
    }

    @Test(arguments: [
        "curl 'https://messages.google.com/web/config' -b 'SID=sid; HSID=hsid'",
        "curl 'https://messages.google.com/web/config'",
        "my shopping list",
        "",
    ])
    func rejectsAnythingWithoutTheWholeSignIn(text: String) {
        #expect(GoogleAccountSignIn.cookies(fromCurl: text) == nil)
    }

    @Test func leavesOutTheCookieThatCanGoStale() {
        let stale = BrowserCookie(name: "__Secure-1PSIDTS", domain: ".google.com", value: "ts")

        #expect(GoogleAccountSignIn.cookies(from: complete + [stale])?.values["__Secure-1PSIDTS"] == nil)
    }

    @Test func leavesOutThatCookieFromAPastedCommandToo() {
        let command = "curl 'https://messages.google.com/web/config' -b 'OSID=o; SID=s; HSID=h; SSID=ss; APISID=a; SAPISID=sa; __Secure-1PSIDTS=ts'"

        #expect(GoogleAccountSignIn.cookies(fromCurl: command)?.values["__Secure-1PSIDTS"] == nil)
        #expect(GoogleAccountSignIn.cookies(fromCurl: command)?.values["SID"] == "s")
    }
}
