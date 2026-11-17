import SwiftUI
import SippyCore

enum MainTab: String, CaseIterable, Identifiable {
    case dialpad, contacts, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dialpad: "Dialpad"
        case .contacts: "Contacts"
        case .history: "History"
        }
    }
}

struct MainView: View {
    @Environment(SIPEngine.self) private var engine
    // Both live here rather than in the tabs so they survive a call (the
    // call screen replaces the tabs) and switching between tabs.
    @ViewState private var tab: MainTab = .dialpad
    @ViewState private var number = ""

    var body: some View {
        // The clear layer sets the usual minimum height. It is a sibling,
        // not a `.frame(minHeight:)` on the content, because that would cap
        // the minimum: the call screen with stats and keypad open is taller,
        // and the window has to grow for it instead of clipping.
        ZStack {
            Color.clear.frame(
                minHeight: SippyLayout.mainMinHeight, idealHeight: SippyLayout.mainIdealHeight)
            content
        }
        .frame(width: SippyLayout.mainWidth)
    }

    private var content: some View {
        VStack(spacing: 0) {
            if engine.call == nil {
                Picker("View", selection: $tab) {
                    ForEach(MainTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 10)
            }
            Divider()
            // One surface for every screen: the lists bring their own text
            // background, so the dialpad and the call screen sit on it too.
            Group {
                if engine.call != nil {
                    CallView()
                } else {
                    switch tab {
                    case .dialpad: DialpadView(number: $number)
                    case .contacts: ContactsView()
                    case .history: HistoryView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            Divider()
            RegistrationStatusBar()
        }
    }
}

/// Bottom status bar of the main window.
struct RegistrationStatusBar: View {
    @Environment(SIPEngine.self) private var engine
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 8) {
            RegistrationStatusLabel()
            Spacer(minLength: 0)
            if case .unconfigured = engine.registration {
                Button("Set Up…") { openSettings() }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
    }
}
