import OSLog
import Presentation
import SwiftUI
import WebKit

/// The Messages website, reporting when it has been signed in and paired.
struct MessagesWebsiteView: NSViewRepresentable {
    let makeWebView: @MainActor () -> WKWebView
    let onPaired: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPaired: onPaired)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = makeWebView()
        webView.uiDelegate = context.coordinator
        context.coordinator.watch(webView)
        webView.load(URLRequest(url: MessagesWebsite.startURL))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKUIDelegate {
        private static let log = Logger(subsystem: "dev.featurenotabug.Relay", category: "phone-wake")

        private let onPaired: @MainActor () -> Void
        private var addressWatch: NSKeyValueObservation?

        init(onPaired: @escaping @MainActor () -> Void) {
            self.onPaired = onPaired
        }

        /// By address rather than page loads, because the site moves between its pages without loading one.
        func watch(_ webView: WKWebView) {
            addressWatch = webView.observe(\.url) { [weak self] webView, _ in
                Self.log.notice("Setup page is at \(webView.url?.host ?? "nothing", privacy: .public)\(webView.url?.path ?? "", privacy: .public)")
                guard let self, MessagesWebsite.isPaired(at: webView.url) else { return }
                self.addressWatch = nil
                self.onPaired()
            }
        }

        /// There's nowhere to put a second window, so anything the site opens replaces the page.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            webView.load(navigationAction.request)
            return nil
        }
    }
}
