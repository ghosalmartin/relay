import AppKit
import LibGMAdapter
import MessagingDomain
import OSLog
import Presentation
import WebKit

/// Wakes the phone by loading the Messages website out of sight, which has worked every time we've tried it
/// in a real browser. Why it works is still unknown, so this does the whole page load rather than a copy of part of it.
@MainActor
final class HiddenMessagesWebsite: PhoneWaker {
    private nonisolated static let setUpKey = "phoneWakeIsSetUp"
    private nonisolated static let log = Logger(subsystem: "dev.featurenotabug.Relay", category: "phone-wake")
    private static let windowSide: CGFloat = 100

    private var window: NSWindow?
    private var addressWatch: NSKeyValueObservation?

    /// WebKit's persistent store, because the site must stay signed in and paired between visits.
    static func makeWebView(frame: NSRect) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let webView = WKWebView(frame: frame, configuration: configuration)
        webView.customUserAgent = GoogleAccountSignIn.userAgent
        return webView
    }

    nonisolated var isSetUp: Bool { UserDefaults.standard.bool(forKey: Self.setUpKey) }

    nonisolated func markSetUp() {
        UserDefaults.standard.set(true, forKey: Self.setUpKey)
    }

    func startWaking() async {
        guard window == nil else { return }
        let frame = Self.cornerOfScreen()
        let webView = Self.makeWebView(frame: NSRect(origin: .zero, size: frame.size))
        addressWatch = webView.observe(\.url) { webView, _ in
            Self.log.notice("Hidden website is at \(webView.url?.path ?? "nothing", privacy: .public), paired: \(MessagesWebsite.isPaired(at: webView.url), privacy: .public)")
        }
        let hidden = Self.invisibleWindow(frame: frame, showing: webView)
        window = hidden
        hidden.orderFrontRegardless()
        Self.log.notice("Loading the website to wake the phone")
        webView.load(URLRequest(url: MessagesWebsite.startURL))
    }

    func stopWaking() async {
        addressWatch = nil
        window?.contentView = nil
        window?.close()
        window = nil
        Self.log.notice("Closed the hidden website")
    }

    func forget() async {
        await stopWaking()
        UserDefaults.standard.removeObject(forKey: Self.setUpKey)
        await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    private static func cornerOfScreen() -> NSRect {
        let origin = NSScreen.main?.visibleFrame.origin ?? .zero
        return NSRect(origin: origin, size: NSSize(width: windowSide, height: windowSide))
    }

    /// On screen, in front and all but transparent, because WebKit suspends a page it thinks nobody can see.
    private static func invisibleWindow(frame: NSRect, showing webView: WKWebView) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0.01
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.contentView = webView
        return window
    }
}
