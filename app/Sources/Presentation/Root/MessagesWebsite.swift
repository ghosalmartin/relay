import Foundation

/// The rules for the website Relay loads to wake a stalled phone.
public enum MessagesWebsite {
    public static let startURL = URL(string: "https://messages.google.com/web")!

    /// The site only shows conversations to a browser that is signed in and paired with the phone.
    public static func isPaired(at url: URL?) -> Bool {
        url?.host == "messages.google.com" && url?.path.hasPrefix("/web/conversations") == true
    }
}
