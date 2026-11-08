import AppKit

/// App-lifetime hooks. The session lives here rather than in a view, so messages keep
/// arriving and alerts keep firing after the window is closed.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment.forCurrentLaunch()

    func applicationWillFinishLaunching(_ notification: Notification) {
        environment.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        environment.setAppActive(true)
    }

    func applicationDidResignActive(_ notification: Notification) {
        environment.setAppActive(false)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
