import ServiceManagement
import SwiftUI

/// Settings → General: login item, where the app shows itself, and how the
/// main window looks.
struct GeneralSettingsTab: View {
    @AppStorage(AppPresence.defaultsKey) private var presenceRaw = AppPresence.dockAndMenuBar.rawValue
    @AppStorage(SippyScheme.defaultsKey) private var scheme = SippyScheme.enamel
    @AppStorage(SippyMode.defaultsKey) private var mode = SippyMode.dark
    @AppStorage(SippyNavigation.defaultsKey) private var navigation = SippyNavigation.top
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
            Section {
                Picker("Color scheme", selection: $scheme) {
                    ForEach(SippyScheme.allCases) { Text($0.label).tag($0) }
                }
                Picker("Appearance", selection: $mode) {
                    ForEach(SippyMode.allCases) { Text($0.label).tag($0) }
                }
                Picker("Navigation", selection: $navigation) {
                    ForEach(SippyNavigation.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Main Window")
            } footer: {
                SettingsFootnote("The registration status takes the end of the window the navigation leaves free.")
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
