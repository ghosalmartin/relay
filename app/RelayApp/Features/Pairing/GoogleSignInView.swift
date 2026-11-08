import LibGMAdapter
import MessagingDomain
import SwiftUI
import WebKit

/// Google's own sign-in page. Uses a throwaway cookie store, so nothing is left behind in WebKit.
struct GoogleSignInView: NSViewRepresentable {
    let onSignedIn: @MainActor (AccountCookies) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSignedIn: onSignedIn)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = GoogleAccountSignIn.userAgent
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: GoogleAccountSignIn.startURL))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onSignedIn: @MainActor (AccountCookies) -> Void

        init(onSignedIn: @escaping @MainActor (AccountCookies) -> Void) {
            self.onSignedIn = onSignedIn
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard webView.url?.host == GoogleAccountSignIn.completionHost else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [onSignedIn] cookies in
                let browserCookies = cookies.map { BrowserCookie(name: $0.name, domain: $0.domain, value: $0.value) }
                if let account = GoogleAccountSignIn.cookies(from: browserCookies) {
                    onSignedIn(account)
                }
            }
        }
    }
}
