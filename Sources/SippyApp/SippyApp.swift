import SwiftUI
import SippyCore

@main
struct SippyApp: App {
    @State private var engine = SIPEngine()
    @State private var systemContacts = SystemContactsIndex()
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup("Sippy") {
            MainView()
                .environment(engine)
                .environment(systemContacts)
                .environment(store)
                .onAppear {
                    wireUp()
                    engine.start()
                    systemContacts.loadIfAuthorized()
                }
                .frame(minWidth: 320, minHeight: 480)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environment(engine)
        }
    }

    /// Caller-ID resolution and history recording live at the app layer so
    /// the engine stays free of storage concerns.
    private func wireUp() {
        let store = store
        let systemContacts = systemContacts

        engine.displayNameResolver = { number in
            if let name = store.contactName(forNumber: number) { return name }
            for entry in systemContacts.entries {
                if entry.numbers.contains(where: { PhoneNumberMatcher.matches($0.value, number) }) {
                    return entry.name
                }
            }
            return nil
        }

        engine.onCallFinished = { finished in
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
        }
    }
}
