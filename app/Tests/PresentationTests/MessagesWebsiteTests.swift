import Foundation
import Presentation
import Testing

@Suite struct MessagesWebsiteTests {
    @Test(arguments: [
        ("https://messages.google.com/web/conversations", true),
        ("https://messages.google.com/web/conversations/123", true),
        ("https://messages.google.com/web/authentication", false),
        ("https://messages.google.com/web", false),
        ("https://accounts.google.com/web/conversations", false),
    ])
    func recognisesAPairedSite(address: String, expected: Bool) {
        #expect(MessagesWebsite.isPaired(at: URL(string: address)) == expected)
    }

    @Test func nothingLoadedIsNotPaired() {
        #expect(!MessagesWebsite.isPaired(at: nil))
    }
}
