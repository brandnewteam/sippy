import ServiceManagement
import SwiftUI

/// Settings → General: login item and where the app shows itself.
struct GeneralSettingsTab: View {
    @AppStorage(AppPresence.defaultsKey) private var presenceRaw = AppPresence.dockAndMenuBar.rawValue
    @ViewState private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @ViewState private var loginItemError: String?

    var body: some View {
        SettingsPane {
            Section {
                Toggle("Start Sippy at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
                Picker("Show Sippy in", selection: Binding(
                    get: { AppPresence(rawValue: presenceRaw) ?? .dockAndMenuBar },
                    set: { presence in
                        presenceRaw = presence.rawValue
                        presence.apply()
                    }
                )) {
                    ForEach(AppPresence.allCases) { Text($0.label).tag($0) }
                }
            } footer: {
                SettingsFootnote {
                    if let loginItemError {
                        Text(loginItemError).foregroundStyle(.red)
                    }
                    Text("A phone should be reachable — start at login and keep Sippy in the menu bar to take calls without any window open.")
                    if AppPresence(rawValue: presenceRaw) == .menuBarOnly {
                        Text("Without a Dock icon, use the menu bar phone icon to open Sippy.")
                    }
                }
            }
        }
        .onAppear {
            // The user can also flip the login item in System Settings.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        loginItemError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginItemError = "Could not update the login item: \(error.localizedDescription)"
        }
    }
}
