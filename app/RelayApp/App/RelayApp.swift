import SwiftUI

@main
struct RelayApp: App {
    @State private var environment = AppEnvironment.forCurrentLaunch()

    var body: some Scene {
        WindowGroup("Messages") {
            RootView(environment: environment)
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowToolbarStyle(.unified)
    }
}
