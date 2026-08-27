import AppKit
import SwiftUI
import SippyCore

@main
struct SippyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Sippy", id: "main") {
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

        // Debug window; listed in the Window menu.
        Window("SIP Log", id: "sip-log") {
            SIPLogView()
                .environment(appDelegate.engine)
        }
        .keyboardShortcut("l", modifiers: [.command, .shift])

        // Registration status + quick dial while the main window is closed
        // (the engine keeps running window-less since M3).
        MenuBarExtra {
            MenuBarView()
                .environment(appDelegate.engine)
                .environment(appDelegate.store)
        } label: {
            MenuBarIcon()
                .environment(appDelegate.engine)
        }

        Settings {
            SettingsView()
                .environment(appDelegate.engine)
                .environment(appDelegate.ringtones)
        }
    }
}
