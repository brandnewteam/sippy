import AppKit
import SwiftUI
import SippyCore

@main
struct SippyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppPresence.defaultsKey) private var presenceRaw = AppPresence.dockAndMenuBar.rawValue

    /// Two-way: Settings drives it via AppStorage, and if the user removes
    /// the extra some other way we fall back to Dock-only so the app never
    /// becomes unreachable.
    private var menuBarInserted: Binding<Bool> {
        Binding(
            get: { AppPresence(rawValue: presenceRaw)?.showsMenuBarExtra ?? true },
            set: { inserted in
                let current = AppPresence(rawValue: presenceRaw) ?? .dockAndMenuBar
                let presence: AppPresence =
                    inserted
                    ? (current == .dockOnly ? .dockAndMenuBar : current)
                    : .dockOnly
                // MenuBarExtra(isInserted:) writes this binding back on every
                // scene update; an unconditional write re-invalidates the
                // scene body and loops forever, pegging the main thread.
                guard presence != current else { return }
                presenceRaw = presence.rawValue
                presence.apply()
            })
    }

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
                .frame(minWidth: 260, minHeight: 440)
        }
        .windowResizability(.contentSize)
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
        }

        // Debug window; listed in the Window menu.
        Window("SIP Log", id: "sip-log") {
            SIPLogView()
                .environment(appDelegate.engine)
        }
        .keyboardShortcut("l", modifiers: [.command, .shift])

        // Registration status + quick dial while the main window is closed
        // (the engine keeps running window-less since M3).
        MenuBarExtra(isInserted: menuBarInserted) {
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
