import AppKit

/// Where the app shows itself. Menu-bar-only uses the accessory activation
/// policy (no Dock icon, no Cmd-Tab entry) — the menu bar extra is then the
/// way back in, so the two can never both be off.
enum AppPresence: String, CaseIterable, Identifiable {
    case dockAndMenuBar
    case dockOnly
    case menuBarOnly

    static let defaultsKey = "sippy.presence"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dockAndMenuBar: "Dock and menu bar"
        case .dockOnly: "Dock only"
        case .menuBarOnly: "Menu bar only"
        }
    }

    var showsMenuBarExtra: Bool { self != .dockOnly }

    static var current: AppPresence {
        UserDefaults.standard.string(forKey: defaultsKey)
            .flatMap(AppPresence.init(rawValue:)) ?? .dockAndMenuBar
    }

    /// Persists and applies the Dock half; the menu bar half is SwiftUI's
    /// `MenuBarExtra(isInserted:)` reading `showsMenuBarExtra`.
    func apply() {
        // Only touch defaults on a real change: a same-value write still
        // notifies @AppStorage and can re-trigger the scene update that
        // called us.
        if Self.current != self {
            UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
        }
        let policy: NSApplication.ActivationPolicy = self == .menuBarOnly ? .accessory : .regular
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
            // Leaving .regular pushes the app behind others; keep whatever
            // window drove the change (usually Settings) in front.
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
