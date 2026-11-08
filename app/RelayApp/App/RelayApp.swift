import SwiftUI

@main
struct RelayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Messages", id: MainWindowOpener.windowID) {
            RootView(environment: appDelegate.environment)
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowToolbarStyle(.unified)
        .commands { AppCommands(windowOpener: appDelegate.environment.windowOpener) }
    }
}
