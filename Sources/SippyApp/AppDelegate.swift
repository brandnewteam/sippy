import AppKit
import SippyCore

/// Owns the app's long-lived objects and starts the SIP engine at launch.
/// Startup must NOT live in a view's onAppear: a softphone has to register
/// and take incoming calls even when it launches without any window (e.g.
/// after the user quit it window-less and state restoration brings none
/// back). Also hosts the Services menu provider.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = SIPEngine()
    let store = AppStore()
    let systemContacts = SystemContactsIndex()
    let ringtones = RingtoneLibrary()
    private(set) lazy var notifier = CallNotifier(engine: engine)

    /// Sparkle auto-updates. Nil when Info.plist has no SUFeedURL (a bare
    /// `swift run`, or a fork without a feed) — see README "Sparkle updates".
    private(set) var updates: UpdateController?
    private var statusItem: StatusItemController?

    var updatesConfigured: Bool { updates != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppPresence.current.apply()
        wireUp()
        notifier.start()
        if UpdateController.isConfigured {
            updates = UpdateController(engine: engine, notifier: notifier)
        }
        statusItem = StatusItemController(
            engine: engine, store: store,
            checkForUpdates: updates.map { updates in { updates.checkForUpdates() } })
        engine.setRingtonePath(ringtones.ringtone(named: engine.account.ringtone)?.url.path)
        engine.start()
        systemContacts.loadIfAuthorized()
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    /// Caller-ID resolution and history recording live here so the engine
    /// stays free of storage concerns.
    private func wireUp() {
        let store = store
        let systemContacts = systemContacts
        let notifier = notifier

        engine.displayNameResolver = { number in
            if let name = store.contactName(forNumber: number) { return name }
            for entry in systemContacts.entries {
                if entry.numbers.contains(where: { PhoneNumberMatcher.matches($0.value, number) }) {
                    return entry.name
                }
            }
            return nil
        }

        engine.onCallFinished = { [weak self] finished in
            let outcome: CallRecord.Outcome
            if finished.connectedAt != nil {
                outcome = .answered
            } else if finished.errorMessage != nil {
                outcome = .failed
            } else if finished.direction == .incoming {
                outcome = finished.wasDeclinedLocally ? .declined : .missed
            } else {
                outcome = .unanswered
            }
            let duration = finished.connectedAt.map { Int(finished.endedAt.timeIntervalSince($0)) } ?? 0
            store.add(CallRecord(
                date: finished.ringStartedAt,
                direction: finished.direction == .incoming ? .incoming : .outgoing,
                number: finished.remoteNumber,
                displayName: finished.remoteDisplay,
                durationSeconds: duration,
                outcome: outcome,
                codec: finished.codec))
            if outcome == .missed {
                notifier.postMissedCall(display: finished.remoteDisplay, number: finished.remoteNumber)
            }
            self?.updates?.callFinished()
        }
    }

    /// A softphone keeps running (and taking calls) with every window closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updates?.checkForUpdates()
    }

    /// Matches NSMessage "callWithSippy" in the NSServices Info.plist entry.
    @objc func callWithSippy(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let text = pasteboard.string(forType: .string),
              let request = DialRequest.parse(text: text)
        else {
            error.pointee = "No phone number in the selection." as NSString
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        engine.handle(request)
    }
}
