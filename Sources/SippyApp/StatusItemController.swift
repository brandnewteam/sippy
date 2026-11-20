import AppKit
import SwiftUI
import SippyCore

/// A left click toggles Sippy's main window. A right click (or Control-
/// click) opens the menu with registration state, current-call quick
/// actions, favorite-contact speed dial and window/update/quit plumbing.
///
/// AppKit rather than SwiftUI's MenuBarExtra, which opens its menu on any
/// click and handles the left click before the app ever sees the event.
/// A SwiftUI view hosted in the icon's button captures `openWindow` and
/// `openSettings` at launch — AppKit has no way to open SwiftUI scenes —
/// so the main window reopens even when Sippy started without it.
@MainActor
final class StatusItemController: NSObject {
    private let engine: SIPEngine
    private let store: AppStore
    private let checkForUpdates: (() -> Void)?
    private let item: NSStatusItem
    private var visibilityObservation: NSKeyValueObservation?

    init(engine: SIPEngine, store: AppStore, checkForUpdates: (() -> Void)?) {
        self.engine = engine
        self.store = store
        self.checkForUpdates = checkForUpdates
        // Fits the widest phone badge. AppKit adds its own side margins.
        item = NSStatusBar.system.statusItem(withLength: 18)
        super.init()

        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            let capturer = PassThroughHostingView(rootView: SceneActionsCapturer())
            capturer.frame = button.bounds
            capturer.autoresizingMask = [.width, .height]
            button.addSubview(capturer)
        }
        observeIcon()

        // Settings › General › Presence decides whether the icon shows.
        item.behavior = .removalAllowed
        applyPresence()
        NotificationCenter.default.addObserver(
            self, selector: #selector(defaultsChanged),
            name: UserDefaults.didChangeNotification, object: nil)
        // ⌘-dragging the icon out of the menu bar: fall back to Dock-only
        // so the app never becomes unreachable.
        visibilityObservation = item.observe(\.isVisible) { [weak self] item, _ in
            let visible = item.isVisible
            MainActor.assumeIsolated { self?.visibilityChanged(visible) }
        }
    }

    // MARK: Presence

    @objc private func defaultsChanged() {
        applyPresence()
    }

    private func applyPresence() {
        let visible = AppPresence.current.showsMenuBarExtra
        if item.isVisible != visible { item.isVisible = visible }
    }

    private func visibilityChanged(_ visible: Bool) {
        guard !visible, AppPresence.current.showsMenuBarExtra else { return }
        AppPresence.dockOnly.apply()
    }

    // MARK: Icon

    /// Re-armed after every change: `withObservationTracking` fires once.
    private func observeIcon() {
        let symbol = withObservationTracking {
            Self.symbol(call: engine.call, registration: engine.registration)
        } onChange: { [weak self] in
            // onChange runs before the new value is stored.
            Task { @MainActor in self?.observeIcon() }
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Sippy")
        image?.isTemplate = true
        item.button?.image = image
    }

    private static func symbol(
        call: SIPEngine.CallInfo?, registration: SIPEngine.RegistrationStatus
    ) -> String {
        if call != nil { return "phone.connection.fill" }
        switch registration {
        case .registered: return "phone.fill"
        case .connecting: return "phone.badge.clock"
        case .failed: return "phone.down.fill"
        case .unconfigured: return "phone"
        case .waitingForRoute: return "phone.badge.waveform"
        }
    }

    // MARK: Clicks

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            MainWindow.toggle()
        }
    }

    /// Built fresh each time, so it shows the state of the moment. Attached
    /// only while open: with a menu set, every click would open it.
    private func showMenu() {
        item.menu = makeMenu()
        item.button?.performClick(nil)
        item.menu = nil
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(.label(statusText))

        if let call = engine.call {
            menu.addItem(.separator())
            menu.addItem(.label(Self.callLine(call)))
            if call.phase == .ringingIncoming {
                menu.addItem(.action("Answer") { [engine] in
                    engine.answer()
                    MainWindow.show(activating: true)
                })
                menu.addItem(.action("Decline") { [engine] in engine.decline() })
            } else {
                menu.addItem(.action("Hang Up") { [engine] in engine.hangUp() })
            }
        }

        let favorites = store.contacts.filter(\.isFavorite)
        if !favorites.isEmpty, engine.call == nil {
            menu.addItem(.separator())
            for contact in favorites {
                guard let number = contact.numbers.first else { continue }
                menu.addItem(.action("Call \(contact.name)") { [engine] in
                    engine.dial(number.value, origin: .internalContact)
                    MainWindow.show(activating: true)
                })
            }
        }

        menu.addItem(.separator())
        menu.addItem(.action("Open Sippy", key: "o") { MainWindow.show(activating: true) })
        menu.addItem(.action("Settings…", key: ",") { SettingsWindow.show() })
        // The only way to check by hand when Sippy lives in the menu bar
        // alone (no app menu to reach).
        if let checkForUpdates {
            menu.addItem(.action("Check for Updates…") { checkForUpdates() })
        }
        menu.addItem(.separator())
        menu.addItem(.action("Quit Sippy", key: "q") { NSApp.terminate(nil) })
        return menu
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

    private static func callLine(_ call: SIPEngine.CallInfo) -> String {
        switch call.phase {
        case .ringingIncoming: "Incoming: \(call.remoteDisplay)"
        case .ringingOutgoing: "Calling \(call.remoteDisplay)…"
        case .held, .heldByRemote: "On hold: \(call.remoteDisplay)"
        default: "In call: \(call.remoteDisplay)"
        }
    }
}

/// The Settings window, for code outside its views.
@MainActor
enum SettingsWindow {
    /// Captured by the menu bar icon at launch.
    static var opener: OpenSettingsAction?

    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let opener {
            opener()
        } else if let item = NSApp.mainMenu?.items.first?.submenu?.items
                    .first(where: { $0.keyEquivalent == "," }),
                  let action = item.action {
            // Not captured (the icon is hidden in Dock-only mode): the app
            // menu's own Settings… item, there even when the menu bar isn't.
            NSApp.sendAction(action, to: item.target, from: item)
        }
        // Menu-bar-only (accessory) apps can activate without fronting the
        // window just opened; once it exists, put it in front by name.
        DispatchQueue.main.async {
            NSApp.windows
                .first { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }?
                .makeKeyAndOrderFront(nil)
        }
    }
}

/// Hands SwiftUI's scene actions to AppKit code. Hosted in the menu bar
/// icon, which exists from launch whether or not any window does; the
/// actions keep working after the view that captured them goes away.
private struct SceneActionsCapturer: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear.onAppear {
            MainWindow.opener = openWindow
            SettingsWindow.opener = openSettings
        }
    }
}

/// Lets clicks through to the status item's button underneath.
private final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}

private extension NSMenuItem {
    static func label(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    static func action(_ title: String, key: String = "", handler: @escaping () -> Void) -> NSMenuItem {
        ClosureMenuItem(title, key: key, handler: handler)
    }
}
