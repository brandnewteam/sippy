import AppKit
import Sparkle

/// Sparkle auto-updates, set up so an update never takes focus on its own
/// and never interrupts a call.
///
/// - Scheduled checks use Sparkle's "gentle reminders": a new version shows
///   up as a notification instead of Sparkle's window jumping in front of
///   what you are doing (Sippy starts at login, so "just launched" doesn't
///   mean you are looking at it). Clicking the notification opens
///   Sparkle's window. Check for Updates… always opens it directly.
/// - Relaunching into the new version waits until no call is in progress.
@MainActor
final class UpdateController: NSObject {
    private let engine: SIPEngine
    private let notifier: CallNotifier
    private var controller: SPUStandardUpdaterController!
    /// Sparkle's go-ahead for a relaunch held back by a call.
    private var postponedRelaunch: (() -> Void)?

    init(engine: SIPEngine, notifier: CallNotifier) {
        self.engine = engine
        self.notifier = notifier
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        notifier.onShowUpdate = { [weak self] in self?.checkForUpdates() }
    }

    /// The build has an update feed (a bare `swift run` doesn't).
    static var isConfigured: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)?.isEmpty == false
    }

    /// Always on request (a menu item or the reminder notification), so it
    /// brings Sippy forward: from the menu bar, Sparkle's window would
    /// otherwise open behind the app you are in.
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    /// Called when a call ends: a relaunch that was waiting for it goes ahead.
    /// The engine reports the end before clearing `call`, hence the hop.
    func callFinished() {
        Task { @MainActor in
            guard engine.call == nil, let relaunch = postponedRelaunch else { return }
            postponedRelaunch = nil
            relaunch()
        }
    }
}

extension UpdateController: SPUUpdaterDelegate {
    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        guard engine.call != nil else { return false }
        postponedRelaunch = installHandler
        return true
    }
}

extension UpdateController: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Always ours: Sparkle would show its window in focus right after
        // launch, which for a login item means stealing it.
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        notifier.postUpdateAvailable(version: update.displayVersionString)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        notifier.removeUpdateAvailable()
    }

    func standardUserDriverWillFinishUpdateSession() {
        notifier.removeUpdateAvailable()
    }
}
