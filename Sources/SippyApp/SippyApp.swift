import AppKit
import SwiftUI
import SippyCore

@main
struct SippyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(MainWindowFloat.defaultsKey) private var floatsOnTop = false

    var body: some Scene {
        // A single Window (not a WindowGroup): openWindow(id:) then fronts
        // the existing window instead of spawning another one.
        Window("Sippy", id: "main") {
            MainView()
                .environment(appDelegate.engine)
                .environment(appDelegate.systemContacts)
                .environment(appDelegate.store)
                .onOpenURL { url in
                    if let request = DialRequest.parse(url) {
                        appDelegate.engine.handle(request)
                    }
                }
        }
        // No title bar of its own: the theme's pane runs to the top edge
        // and MainView puts the tabs (or the status) beside the traffic
        // lights.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: SippyLayout.mainWidth, height: SippyLayout.mainIdealHeight)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { appDelegate.checkForUpdates(nil) }
                    .disabled(!appDelegate.updatesConfigured)
            }
            CommandGroup(after: .pasteboard) {
                Button("Paste and Dial") {
                    if let text = NSPasteboard.general.string(forType: .string),
                       let request = DialRequest.parse(text: text) {
                        appDelegate.engine.handle(request)
                    }
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
            // Under Minimize and Zoom; a checkmark shows when it is on.
            CommandGroup(after: .windowSize) {
                Toggle("Float on Top", isOn: $floatsOnTop)
            }
        }

        // Debug window; listed in the Window menu.
        Window("SIP Log", id: "sip-log") {
            SIPLogView()
                .environment(appDelegate.engine)
        }
        .keyboardShortcut("l", modifiers: [.command, .shift])

        // The menu bar icon is AppKit: see StatusItemController.

        Settings {
            SettingsView()
                .environment(appDelegate.engine)
                .environment(appDelegate.ringtones)
        }
    }
}
