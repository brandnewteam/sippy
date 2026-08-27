import SwiftUI

@main
struct SippyApp: App {
    @State private var engine = SIPEngine()

    var body: some Scene {
        WindowGroup("Sippy") {
            MainView()
                .environment(engine)
                .onAppear { engine.start() }
                .frame(minWidth: 300, minHeight: 460)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environment(engine)
        }
    }
}
