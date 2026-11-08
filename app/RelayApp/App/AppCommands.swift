import SwiftUI

/// Menu changes for a single-window app.
struct AppCommands: Commands {
    let windowOpener: MainWindowOpener
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Commands stay alive with no windows open, so this is the one place that can always
        // get at SwiftUI's openWindow action.
        let _ = windowOpener.open = { [openWindow] in openWindow(id: MainWindowOpener.windowID) }
        CommandGroup(replacing: .newItem) {}
    }
}
