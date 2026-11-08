import AppKit
import LibGMAdapter
import Presentation
import SwiftUI

/// Signing in through Chrome, where passkeys work, then bringing the session back by clipboard.
struct BrowserSignInView: View {
    let problem: String?
    let onPaste: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button("Open Chrome to Sign In", action: Self.openChrome)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("pairing.openChrome")
            ForEach(PairingState.browserSteps, id: \.self) { step in
                Text(step).fixedSize(horizontal: false, vertical: true)
            }
            Button("Paste from Chrome", action: onPaste)
                .accessibilityIdentifier("pairing.paste")
            if let problem {
                Text(problem).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Text("Relay wipes the clipboard after reading it. Don't sign out in Chrome afterwards, or Relay's login ends too.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 360, alignment: .leading)
    }

    private static func openChrome() {
        let workspace = NSWorkspace.shared
        guard let chrome = workspace.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
            workspace.open(GoogleAccountSignIn.startURL)     // any browser can do this
            return
        }
        workspace.open([GoogleAccountSignIn.startURL], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
    }
}
