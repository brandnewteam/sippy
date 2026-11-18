import AppKit
import SwiftUI
import SippyCore

/// Menu bar icon: reflects registration and call state. A View (not a plain
/// computed string in the App) so Observation reliably re-renders it.
struct MenuBarIcon: View {
    @Environment(SIPEngine.self) private var engine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: symbol)
            // Lives as long as the menu bar extra, so the notifier can
            // reopen a closed main window.
            .onAppear { MainWindow.opener = openWindow }
    }

    private var symbol: String {
        if engine.call != nil { return "phone.connection.fill" }
        switch engine.registration {
        case .registered: return "phone.fill"
        case .connecting: return "phone.badge.clock"
        case .failed: return "phone.down.fill"
        case .unconfigured: return "phone"
        case .waitingForRoute: return "phone.badge.waveform"
        }
    }
}

/// Left click on the menu bar icon opens Sippy; right click (or Control-
/// click) opens the menu. SwiftUI's MenuBarExtra opens its menu on any
/// click, so a local event monitor takes the plain left click first. The
/// icon is the app's only window at the status bar level.
@MainActor
enum MenuBarClicks {
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard event.window?.level == .statusBar,
                  !event.modifierFlags.contains(.control)
            else { return event }
            MainActor.assumeIsolated { MainWindow.show(activating: true) }
            return nil
        }
    }
}

/// Contents of the menu bar extra: registration state, current-call quick
/// actions, favorite-contact speed dial, and window/quit plumbing.
struct MenuBarView: View {
    /// Nil when the build has no update feed.
    var checkForUpdates: (() -> Void)?

    @Environment(SIPEngine.self) private var engine
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            Text(statusText)

            if let call = engine.call {
                Divider()
                Text(callLine(call))
                if call.phase == .ringingIncoming {
                    Button("Answer") { engine.answer(); showMainWindow() }
                    Button("Decline") { engine.decline() }
                } else {
                    Button("Hang Up") { engine.hangUp() }
                }
            }

            let favorites = store.contacts.filter(\.isFavorite)
            if !favorites.isEmpty, engine.call == nil {
                Divider()
                ForEach(favorites) { contact in
                    if let number = contact.numbers.first {
                        Button("Call \(contact.name)") {
                            engine.dial(number.value, origin: .internalContact)
                            showMainWindow()
                        }
                    }
                }
            }

            Divider()
            Button("Open Sippy") { showMainWindow() }
                .keyboardShortcut("o")
            // Not a SettingsLink: the menu leaves Sippy inactive, so the
            // window it opened landed behind the app you were in.
            Button("Settings…") { showSettings() }
                .keyboardShortcut(",")
            // The only way to check by hand when Sippy lives in the menu bar
            // alone (no app menu to reach).
            if let checkForUpdates {
                Button("Check for Updates…") { checkForUpdates() }
            }
            Divider()
            Button("Quit Sippy") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private var statusText: String {
        switch engine.registration {
        case .registered: "Registered — \(engine.account.username)@\(engine.account.domain)"
        case .connecting: "Registering…"
        case .failed(let message): "Registration failed: \(message)"
        case .unconfigured: "No account configured"
        case .waitingForRoute: "Waiting for a route to the server (VPN down?)"
        }
    }

    private func callLine(_ call: SIPEngine.CallInfo) -> String {
        switch call.phase {
        case .ringingIncoming: "Incoming: \(call.remoteDisplay)"
        case .ringingOutgoing: "Calling \(call.remoteDisplay)…"
        case .held, .heldByRemote: "On hold: \(call.remoteDisplay)"
        default: "In call: \(call.remoteDisplay)"
        }
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        // Menu-bar-only (accessory) apps can activate without fronting the
        // window just opened; once it exists, put it in front by name.
        DispatchQueue.main.async {
            NSApp.windows
                .first { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }?
                .makeKeyAndOrderFront(nil)
        }
    }
}
