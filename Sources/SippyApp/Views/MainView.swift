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

extension MainTab {
    var symbol: String {
        switch self {
        case .dialpad: "circle.grid.3x3.fill"
        case .contacts: "person.fill"
        case .history: "clock.fill"
        }
    }
}

struct MainView: View {
    @Environment(SIPEngine.self) private var engine
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SippyScheme.defaultsKey) private var schemeRaw = SippyScheme.enamel.rawValue
    @AppStorage(SippyMode.defaultsKey) private var modeRaw = SippyMode.dark.rawValue
    @AppStorage(SippyNavigation.defaultsKey) private var navigationRaw = SippyNavigation.top.rawValue
    @AppStorage(MainWindowFloat.defaultsKey) private var floatsOnTop = false
    // Both live here rather than in the tabs so they survive a call (the
    // call screen replaces the tabs) and switching between tabs.
    @ViewState private var tab: MainTab = .dialpad
    @ViewState private var number = ""
    @ViewState private var chrome = WindowChromeMetrics()

    private var mode: SippyMode { SippyMode(rawValue: modeRaw) ?? .dark }
    private var navigation: SippyNavigation { SippyNavigation(rawValue: navigationRaw) ?? .top }

    /// Dark or light, with "Match System" already resolved.
    private var colorScheme: ColorScheme {
        mode.colorScheme ?? (SystemAppearance.shared.isDark ? .dark : .light)
    }

    private var theme: SippyTheme {
        .resolve(SippyScheme(rawValue: schemeRaw) ?? .enamel, dark: colorScheme == .dark)
    }

    var body: some View {
        let theme = theme
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
        // The window is one pane of the theme's color: the content runs
        // under the (hidden) title bar, whose strip `topStrip` fills in.
        .ignoresSafeArea(.container, edges: .top)
        .background {
            LinearGradient(
                colors: [theme.paneTop, theme.paneBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        // `.secondary` and `.tertiary` in the views below resolve to these.
        .foregroundStyle(theme.ink, theme.dim, theme.faint)
        .tint(theme.accent)
        .environment(\.sippyTheme, theme)
        // The whole window, not just our drawing: sheets, menus, the text
        // cursor and placeholders have to match the pane. SwiftUI owns the
        // window's appearance, so it is asked rather than set behind its
        // back; always with a definite answer, because a window released
        // back to "no preference" keeps the last one.
        .preferredColorScheme(colorScheme)
        .background(WindowChrome(metrics: $chrome, floats: floatsOnTop) {
            // A hosting view of its own: it gets none of our environment.
            titlebar
                .foregroundStyle(theme.ink, theme.dim, theme.faint)
                .environment(\.sippyTheme, theme)
                .environment(engine)
        })
        // For the call notification, when the menu bar extra is off.
        .onAppear { MainWindow.opener = openWindow }
    }

    private var content: some View {
        VStack(spacing: 0) {
            // The title bar's strip; `titlebar` is drawn in it.
            Color.clear.frame(height: chrome.titlebarHeight)
            // Why the last call failed. Here rather than in one tab: a call
            // placed from Contacts or History comes back to that tab.
            if engine.call == nil, let error = engine.lastCallError {
                CallErrorBanner(message: error) { engine.clearLastCallError() }
            }
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
            switch navigation {
            case .top:
                RegistrationStatusBar()
            case .bottom:
                // The call screen replaces the tabs, so there is nowhere to
                // switch to.
                if engine.call == nil { BottomTabBar(tab: $tab) }
            }
        }
    }

    /// What sits in the title bar, right of the traffic lights: the tabs, or
    /// the registration status when the tabs are at the bottom.
    @ViewBuilder
    private var titlebar: some View {
        switch navigation {
        case .top:
            // The call screen replaces the tabs, so there is nowhere to
            // switch to.
            if engine.call == nil {
                TopTabs(tab: $tab)
                    .padding(.leading, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        case .bottom:
            RegistrationStatusChip { openSettings() }
                // Centered in the window, not in the space the traffic
                // lights leave.
                .padding(.trailing, max(chrome.leading - chrome.trailing, 0))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The three screens as text tabs in the title bar; the selected one is
/// underlined in the accent.
struct TopTabs: View {
    @Environment(\.sippyTheme) private var theme
    @Binding var tab: MainTab

    var body: some View {
        HStack(spacing: 16) {
            ForEach(MainTab.allCases) { item in
                let selected = item == tab
                Button {
                    tab = item
                } label: {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(selected ? theme.ink : theme.dim)
                        .padding(.vertical, 4)
                        .overlay(alignment: .bottom) {
                            Capsule().fill(selected ? theme.accent : .clear).frame(height: 2)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// The three screens as a tab bar along the bottom of the window.
struct BottomTabBar: View {
    @Environment(\.sippyTheme) private var theme
    @Binding var tab: MainTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases) { item in
                let selected = item == tab
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(selected ? theme.callGlyph : theme.dim)
                            .frame(width: 46, height: 24)
                            .background(Capsule().fill(selected ? theme.callFill : .clear))
                        Text(item.title)
                            .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? theme.accent : theme.dim)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .background(theme.barFill)
        .overlay(alignment: .top) { theme.hairline.frame(height: 1) }
    }
}

/// The failure reason of the last call, until dismissed or the next call.
/// SIP reasons can be long ("SIP 480 Temporarily Unavailable — Reason: …"),
/// so it wraps instead of truncating.
struct CallErrorBanner: View {
    @Environment(\.sippyTheme) private var theme
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.danger)
            VStack(alignment: .leading, spacing: 1) {
                Text("Call failed").fontWeight(.medium)
                Text(message)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .font(.callout)
            Spacer(minLength: 4)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.danger.opacity(0.14))
        .help(message)
    }
}

/// Bottom status bar of the main window, when the tabs are in the title bar.
struct RegistrationStatusBar: View {
    @Environment(SIPEngine.self) private var engine
    @Environment(\.sippyTheme) private var theme
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
        .overlay(alignment: .top) { theme.hairline.frame(height: 1) }
    }
}

/// The registration status as a chip in the title bar, when the tabs are at
/// the bottom. Without an account it is the way into Settings.
struct RegistrationStatusChip: View {
    @Environment(SIPEngine.self) private var engine
    @Environment(\.sippyTheme) private var theme
    /// Passed in: the title bar is outside the scene's environment.
    let openSettings: () -> Void

    var body: some View {
        if case .unconfigured = engine.registration {
            Button(action: openSettings) { chip }
                .buttonStyle(.plain)
                .help("Set up an account…")
        } else {
            chip
        }
    }

    private var chip: some View {
        RegistrationStatusLabel(font: .system(size: 11.5))
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Capsule().fill(theme.barFill))
            .contentShape(Capsule())
    }
}
