import AppKit
import SwiftUI
import UserNotifications

/// Incoming calls arrive as a notification, never as a window that jumps
/// in front of what you are doing. Clicking the notification brings Sippy
/// forward on the call screen; its Answer and Decline actions act without
/// taking focus. The notification goes away as soon as the call stops
/// ringing, and a call nobody answered leaves a "Missed call" notification.
@MainActor
final class CallNotifier: NSObject, UNUserNotificationCenterDelegate {
    private enum ID {
        static let incomingCategory = "sippy.incoming-call"
        static let missedCategory = "sippy.missed-call"
        static let incomingRequest = "sippy.incoming-call"
        static let answer = "sippy.answer"
        static let decline = "sippy.decline"
    }

    private let engine: SIPEngine
    private let center = UNUserNotificationCenter.current()
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
        ])
        // No sound: the ringtone is already playing.
        center.requestAuthorization(options: [.alert]) { _, _ in }
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
            // Sippy is the active app. With the call screen in sight the
            // banner only repeats it; otherwise (Settings in front, main
            // window closed) it is the only sign of the call.
            if !MainWindow.isInSight {
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
        Task { @MainActor in
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
/// Settings; the app can only read it. Only the persistent style keeps a
/// ringing call on screen until it stops ringing — the temporary one slides
/// away after a few seconds, and the Info.plist default for it is ignored.
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
            "An incoming call shows a notification with Answer and Decline that stays up until the call stops ringing. Sippy never jumps in front of what you are doing."
        case .notAsked, .off:
            "Calls still ring, but without a notification you only see them in the menu bar or the main window. Allow notifications for Sippy in System Settings."
        case .temporary:
            "Temporary notifications slide away while the phone is still ringing. Set Sippy to Persistent (Alerts on older macOS) in System Settings to keep an incoming call on screen until you answer, decline, or the caller hangs up."
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
