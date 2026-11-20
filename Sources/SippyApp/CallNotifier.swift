import AppKit
import SwiftUI
import UserNotifications

/// Presents incoming calls in a nonactivating panel and in Notification
/// Center. Both follow the ringing state. A call nobody answered leaves a
/// "Missed call" notification.
/// It also posts the "update available" reminder for `UpdateController`.
@MainActor
final class CallNotifier: NSObject, UNUserNotificationCenterDelegate {
    private enum ID {
        static let incomingCategory = "sippy.incoming-call"
        static let missedCategory = "sippy.missed-call"
        static let incomingRequest = "sippy.incoming-call"
        static let answer = "sippy.answer"
        static let decline = "sippy.decline"
        static let updateCategory = "sippy.update"
        static let updateRequest = "sippy.update-available"
    }

    /// A click on the "update available" notification.
    var onShowUpdate: (() -> Void)?

    private let engine: SIPEngine
    private let center = UNUserNotificationCenter.current()
    private var incomingPanel: IncomingCallPanel?
    /// The ringing call has a notification up.
    private var notifying = false

    init(engine: SIPEngine) {
        self.engine = engine
    }

    func start() {
        center.delegate = self
        // Answer first: macOS lays the actions out, the order is ours.
        // Neither action has `.foreground`, so neither activates the app.
        let answer = UNNotificationAction(identifier: ID.answer, title: "Answer", options: [])
        let decline = UNNotificationAction(
            identifier: ID.decline, title: "Decline", options: [.destructive])
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: ID.incomingCategory, actions: [answer, decline],
                intentIdentifiers: [], options: []),
            UNNotificationCategory(
                identifier: ID.missedCategory, actions: [], intentIdentifiers: [], options: []),
            UNNotificationCategory(
                identifier: ID.updateCategory, actions: [], intentIdentifiers: [], options: []),
        ])
        // No sound: the ringtone is already playing.
        center.requestAuthorization(options: [.alert]) { _, _ in }
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                     NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(focusChanged), name: name, object: nil)
        }
        observeCall()
    }

    /// Re-armed after every change: `withObservationTracking` fires once.
    private func observeCall() {
        let phase = withObservationTracking {
            engine.call?.phase
        } onChange: { [weak self] in
            // onChange runs before the new value is stored.
            Task { @MainActor in self?.observeCall() }
        }
        update(ringing: phase == .ringingIncoming)
        updateIncomingPanel()
    }

    @objc private func focusChanged() {
        guard engine.call?.phase == .ringingIncoming else { return }
        // A key window change posts resign and become notifications in succession.
        DispatchQueue.main.async { [weak self] in self?.updateIncomingPanel() }
    }

    private func updateIncomingPanel() {
        let usingCallWindow = NSApp.isActive && MainWindow.window?.isKeyWindow == true
        guard engine.call?.phase == .ringingIncoming, !usingCallWindow else {
            incomingPanel?.orderOut(nil)
            incomingPanel = nil
            return
        }
        if incomingPanel == nil {
            let panel = IncomingCallPanel(engine: engine)
            incomingPanel = panel
            panel.present()
        }
    }

    private func update(ringing: Bool) {
        if ringing, !notifying, let call = engine.call {
            notifying = true
            let content = UNMutableNotificationContent()
            content.title = call.remoteDisplay
            content.body = Self.line("Incoming call", call.remoteDisplay, call.remoteNumber)
            content.categoryIdentifier = ID.incomingCategory
            content.threadIdentifier = "calls"
            center.add(UNNotificationRequest(
                identifier: ID.incomingRequest, content: content, trigger: nil))
        } else if !ringing, notifying {
            // Answered (here or elsewhere), declined, or the caller gave up.
            notifying = false
            center.removePendingNotificationRequests(withIdentifiers: [ID.incomingRequest])
            center.removeDeliveredNotifications(withIdentifiers: [ID.incomingRequest])
        }
    }

    func postMissedCall(display: String, number: String) {
        let content = UNMutableNotificationContent()
        content.title = "Missed call"
        content.body = display == number || number.isEmpty ? display : "\(display) · \(number)"
        content.categoryIdentifier = ID.missedCategory
        content.threadIdentifier = "calls"
        center.add(UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func postUpdateAvailable(version: String) {
        let content = UNMutableNotificationContent()
        content.title = "Sippy \(version) is available"
        content.body = "Click to see what’s new and install it."
        content.categoryIdentifier = ID.updateCategory
        center.add(UNNotificationRequest(
            identifier: ID.updateRequest, content: content, trigger: nil))
    }

    func removeUpdateAvailable() {
        center.removePendingNotificationRequests(withIdentifiers: [ID.updateRequest])
        center.removeDeliveredNotifications(withIdentifiers: [ID.updateRequest])
    }

    /// "Incoming call from 204" when the title is a name, plain otherwise.
    private static func line(_ prefix: String, _ display: String, _ number: String) -> String {
        display == number || number.isEmpty ? prefix : "\(prefix) from \(number)"
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let category = notification.request.content.categoryIdentifier
        // Delegate calls may come on any queue.
        Task { @MainActor in
            // Suppress the system banner when the call screen is in sight.
            // Update reminders always get a banner.
            if !MainWindow.isInSight || category == ID.updateCategory {
                completionHandler([.banner, .list])
            } else {
                completionHandler(category == ID.incomingCategory ? [] : [.list])
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        Task { @MainActor in
            if category == ID.updateCategory {
                if action == UNNotificationDefaultActionIdentifier { onShowUpdate?() }
                completionHandler()
                return
            }
            handle(action: action)
            completionHandler()
        }
    }

    private func handle(action: String) {
        let ringing = engine.call?.phase == .ringingIncoming
        switch action {
        case ID.answer where ringing:
            engine.answer()
            // In sight for Hang Up, without taking focus from your work.
            MainWindow.show(activating: false)
        case ID.decline where ringing:
            engine.decline()
        case UNNotificationDefaultActionIdentifier:
            // A click on the notification itself: you asked for Sippy.
            MainWindow.show(activating: true)
        default:
            break
        }
    }
}

/// How macOS shows Sippy's notifications. The user sets it in System
/// Settings. The floating call panel works independently of this style.
enum CallNotificationStyle {
    case unknown, notAsked, off, temporary, persistent

    static func current() async -> CallNotificationStyle {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notAsked
        case .denied: return .off
        default: break
        }
        switch settings.alertStyle {
        case .alert: return .persistent
        case .banner: return .temporary
        default: return .off
        }
    }

    var label: String {
        switch self {
        case .unknown: ""
        case .notAsked: "Not set up"
        case .off: "Off"
        case .temporary: "Temporary"
        case .persistent: "Persistent"
        }
    }

    var footnote: String {
        switch self {
        case .unknown, .persistent:
            "Incoming call notifications offer Answer and Decline. You can also answer from the floating call panel while working in another app."
        case .notAsked, .off:
            "The floating panel shows incoming calls. Allow notifications in System Settings to see calls in Notification Center as well."
        case .temporary:
            "Temporary notifications disappear after a few seconds. The floating call panel stays available while the call rings."
        }
    }

    static func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The main window, for code outside its views: the notifier and the menu
/// bar bring it forward.
@MainActor
enum MainWindow {
    /// Set by the window chrome probe that lives in it.
    static weak var window: NSWindow?
    /// Captured from views that have it, for when the window is closed.
    static var opener: OpenWindowAction?

    /// Open and on screen, with Sippy the active app.
    static var isInSight: Bool {
        guard NSApp.isActive, let window else { return false }
        return window.isVisible && !window.isMiniaturized
    }

    static func toggle() {
        if let window, window.isVisible, !window.isMiniaturized, !NSApp.isHidden {
            window.performClose(nil)
        } else {
            show(activating: true)
        }
    }

    /// `activating: false` only orders an open window to the front;
    /// opening a closed one would take focus, so it stays closed.
    static func show(activating: Bool) {
        if let window, window.isVisible, !window.isMiniaturized {
            if activating {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }
            return
        }
        guard activating else { return }
        NSApp.activate(ignoringOtherApps: true)
        if let window, window.isMiniaturized {
            window.deminiaturize(nil)
        } else if let opener {
            opener(id: "main")
        } else if let item = NSApp.windowsMenu?.items.first(where: { $0.title == "Sippy" }),
                  let selector = item.action {
            // SwiftUI lists the window in the Window menu even when closed.
            NSApp.sendAction(selector, to: item.target, from: item)
        }
    }
}
