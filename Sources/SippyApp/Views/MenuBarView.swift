import AppKit
import SwiftUI
import SippyCore

/// Menu bar icon: reflects registration and call state. A View (not a plain
/// computed string in the App) so Observation reliably re-renders it.
struct MenuBarIcon: View {
    @Environment(SIPEngine.self) private var engine

    var body: some View {
        Image(systemName: symbol)
    }

    private var symbol: String {
        if engine.call != nil { return "phone.connection.fill" }
        switch engine.registration {
        case .registered: return "phone.fill"
        case .connecting: return "phone.badge.clock"
        case .failed: return "phone.down.fill"
        case .unconfigured: return "phone"
        }
    }
}

/// Contents of the menu bar extra: registration state, current-call quick
/// actions, favorite-contact speed dial, and window/quit plumbing.
struct MenuBarView: View {
    @Environment(SIPEngine.self) private var engine
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow

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
            SettingsLink { Text("Settings…") }
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
}
