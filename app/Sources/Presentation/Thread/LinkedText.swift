import Foundation

/// Finds web links in message text so they can be clicked.
enum LinkedText {
    static func attributed(_ text: String) -> AttributedString {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
        let linked = NSMutableAttributedString(string: text)
        matches
            .filter { isWebLink($0.url) }
            .forEach { linked.addAttribute(linkKey, value: $0.url as Any, range: $0.range) }
        return AttributedString(linked)
    }

    /// `.link` is declared by AppKit, which this layer doesn't import; this is its raw name.
    private static let linkKey = NSAttributedString.Key("NSLink")

    /// Message text is written by other people, so a tap should only ever go to a web page.
    private static func isWebLink(_ url: URL?) -> Bool {
        url?.scheme == "https" || url?.scheme == "http"
    }
}
