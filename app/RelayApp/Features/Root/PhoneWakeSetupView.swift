import SwiftUI
import WebKit

/// The one time the website Relay wakes the phone with is shown, because signing in and pairing need a person.
struct PhoneWakeSetupView: View {
    let makeWebView: @MainActor () -> WKWebView
    let onPaired: @MainActor () -> Void
    let onSkipped: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("One more step").font(.title2.weight(.semibold))
                    Text("Your phone sometimes stops answering Relay, and loading the Messages website gets it going again. Sign in and pair below, once, and Relay will do that out of sight. Press Done when you can see your chats.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Not Now", action: onSkipped)
                    .accessibilityIdentifier("phoneWakeSetup.skip")
                // Spotting a paired site automatically relies on the site's addresses, which Google can change.
                Button("Done", action: onPaired)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("phoneWakeSetup.done")
            }
            MessagesWebsiteView(makeWebView: makeWebView, onPaired: onPaired)
                .clipShape(.rect(cornerRadius: 12))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
