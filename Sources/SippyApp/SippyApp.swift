import AppKit
import SwiftUI
import SippyCore

@main
struct SippyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Sippy") {
            MainView()
                .environment(appDelegate.engine)
                .environment(appDelegate.systemContacts)
                .environment(appDelegate.store)
                .onOpenURL { url in
                    if let request = DialRequest.parse(url) {
                        appDelegate.engine.handle(request)
                    }
                }
                .frame(minWidth: 320, minHeight: 480)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .pasteboard) {
                Button("Paste and Dial") {
                    if let text = NSPasteboard.general.string(forType: .string),
                       let request = DialRequest.parse(text: text) {
                        appDelegate.engine.handle(request)
                    }
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(appDelegate.engine)
        }
    }
}
