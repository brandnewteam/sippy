import AppKit
import SwiftUI

// MARK: - Preferences

/// The main window's look. Each scheme is a palette plus a small shape
/// language (how keys, toggles and list rows are drawn), in a dark and a
/// light variant.
enum SippyScheme: String, CaseIterable, Identifiable {
    /// The app icon's indigo, edge to edge, with its mint as the one accent.
    case enamel
    /// Near-black indigo, outlined round keys, mint for the live numbers.
    case night
    /// Loud: a brighter indigo (dark) or a mint pane (light), bare numerals.
    case vivid

    static let defaultsKey = "sippy.appearance.scheme"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .enamel: "Enamel"
        case .night: "Night Signal"
        case .vivid: "Vivid"
        }
    }
}

/// Which variant of the scheme the main window uses. Dark is the default:
/// it is the one that looks like the icon.
enum SippyMode: String, CaseIterable, Identifiable {
    case dark, light, system

    static let defaultsKey = "sippy.appearance.mode"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "Match System"
        }
    }

    /// nil follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

/// Where the Dialpad / Contacts / History switch sits. The registration
/// status takes the other end of the window.
enum SippyNavigation: String, CaseIterable, Identifiable {
    /// Text tabs in the title bar, status along the bottom.
    case top
    /// Tab bar with icons along the bottom, status in the title bar.
    case bottom

    static let defaultsKey = "sippy.appearance.navigation"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .top: "Top, in the title bar"
        case .bottom: "Bottom, as a tab bar"
        }
    }
}

// MARK: - Theme

/// The resolved look of the main window: every color the views draw with,
/// so none of them reaches for a system color that assumes a gray window.
struct SippyTheme {
    enum KeyShape {
        /// Filled rounded tile.
        case tile
        /// Outlined circle.
        case ring
        /// Just the numeral.
        case bare
    }

    enum RowStyle {
        /// Hairline between rows.
        case ruled
        /// Nothing between rows.
        case plain
        /// Each row on its own rounded card.
        case card
    }

    var scheme: SippyScheme
    var isDark: Bool

    /// The window pane, top to bottom. Equal for a flat pane.
    var paneTop: Color
    var paneBottom: Color

    /// Text levels on the pane: primary, secondary, tertiary.
    var ink: Color
    var dim: Color
    var faint: Color

    /// The highlight on the pane: selected tab, links, the text cursor.
    var accent: Color
    /// Start/answer a call.
    var callFill: Color
    var callGlyph: Color
    /// Edge for a call button whose fill is close to the pane.
    var callRing: Color = .clear
    /// "Registered" and the small call glyphs in list rows.
    var signal: Color
    var warning: Color
    /// Missed calls and failures, as text on the pane.
    var danger: Color
    /// End/decline a call (always with a white glyph).
    var hangUp: Color

    /// Quiet fill: key tiles, toggles, the search field, the stats panel.
    var controlFill: Color
    /// Stroke of outlined keys and toggles.
    var outline: Color = .clear
    /// A toggle that is on.
    var activeFill: Color
    var activeGlyph: Color

    var hairline: Color
    /// Bottom tab bar and the status chip.
    var barFill: Color
    var cardFill: Color

    var keyShape: KeyShape
    var rowStyle: RowStyle

    /// Hover and pressed feedback, laid over whatever the control is filled
    /// with.
    func veil(pressed: Bool, hovering: Bool) -> Color {
        ink.opacity(pressed ? 0.16 : hovering ? 0.07 : 0)
    }

    /// Wide labelled Call / End Call buttons instead of round ones.
    var usesPills: Bool { scheme == .vivid }
    /// The call screen leads with the running timer instead of a monogram.
    var timerHero: Bool { scheme == .night }
    /// The call screen's monogram in the call button's colors.
    var accentedMonogram: Bool { scheme == .vivid || (scheme == .enamel && !isDark) }

    var keyHeight: CGFloat { keyShape == .ring ? 54 : 52 }
    var keyRowSpacing: CGFloat {
        switch keyShape {
        case .tile: 12
        case .ring: 8
        case .bare: 4
        }
    }
}

extension SippyTheme {
    static func resolve(_ scheme: SippyScheme, dark: Bool) -> SippyTheme {
        let indigo = Color(hex: 0x2F2B79)
        let mint = Color(hex: 0x8AEDBD)
        let white = Color.white

        switch (scheme, dark) {
        case (.enamel, true):
            return SippyTheme(
                scheme: scheme, isDark: true,
                paneTop: Color(hex: 0x332F82), paneBottom: Color(hex: 0x2A2670),
                ink: white, dim: white.opacity(0.74), faint: white.opacity(0.45),
                accent: mint, callFill: mint, callGlyph: indigo,
                signal: mint, warning: .orange, danger: Color(hex: 0xFF9A9A), hangUp: Color(hex: 0xF0494F),
                controlFill: white.opacity(0.09), activeFill: white, activeGlyph: indigo,
                hairline: white.opacity(0.09), barFill: Color.black.opacity(0.24), cardFill: white.opacity(0.09),
                keyShape: .tile, rowStyle: .ruled)
        case (.enamel, false):
            let dim = Color(hex: 0x5E5A99)
            return SippyTheme(
                scheme: scheme, isDark: false,
                paneTop: Color(hex: 0xF0EFFA), paneBottom: Color(hex: 0xE8E7F5),
                ink: indigo, dim: dim, faint: dim.opacity(0.6),
                accent: indigo, callFill: indigo, callGlyph: mint,
                signal: Color(hex: 0x129463), warning: Color(hex: 0xB45309),
                danger: Color(hex: 0xB4232F), hangUp: Color(hex: 0xE5484D),
                controlFill: white, activeFill: indigo, activeGlyph: white,
                hairline: indigo.opacity(0.11), barFill: indigo.opacity(0.09), cardFill: white,
                keyShape: .tile, rowStyle: .ruled)
        case (.night, true):
            let ground = Color(hex: 0x121027)
            return SippyTheme(
                scheme: scheme, isDark: true,
                paneTop: ground, paneBottom: ground,
                ink: white, dim: white.opacity(0.66), faint: white.opacity(0.4),
                accent: mint, callFill: mint, callGlyph: ground,
                signal: mint, warning: .orange, danger: Color(hex: 0xFF8F8F), hangUp: Color(hex: 0xF0494F),
                controlFill: white.opacity(0.07), outline: white.opacity(0.2),
                activeFill: mint, activeGlyph: ground,
                hairline: white.opacity(0.1), barFill: white.opacity(0.06), cardFill: white.opacity(0.07),
                keyShape: .ring, rowStyle: .plain)
        case (.night, false):
            let ground = Color(hex: 0xF8F8FC)
            return SippyTheme(
                scheme: scheme, isDark: false,
                paneTop: ground, paneBottom: ground,
                ink: Color(hex: 0x1F1C52), dim: Color(hex: 0x5E5A99), faint: Color(hex: 0x5E5A99).opacity(0.6),
                accent: indigo, callFill: mint, callGlyph: indigo, callRing: indigo.opacity(0.16),
                signal: Color(hex: 0x0F8558), warning: Color(hex: 0xB45309),
                danger: Color(hex: 0xB4232F), hangUp: Color(hex: 0xE5484D),
                controlFill: indigo.opacity(0.06), outline: indigo.opacity(0.24),
                activeFill: indigo, activeGlyph: mint,
                hairline: indigo.opacity(0.1), barFill: indigo.opacity(0.06), cardFill: indigo.opacity(0.05),
                keyShape: .ring, rowStyle: .plain)
        case (.vivid, true):
            return SippyTheme(
                scheme: scheme, isDark: true,
                paneTop: Color(hex: 0x4A3FC4), paneBottom: indigo,
                ink: white, dim: white.opacity(0.8), faint: white.opacity(0.5),
                accent: mint, callFill: mint, callGlyph: indigo,
                signal: mint, warning: .orange, danger: Color(hex: 0xFFB0B0), hangUp: Color(hex: 0xD5343B),
                controlFill: white.opacity(0.14), activeFill: white, activeGlyph: indigo,
                hairline: white.opacity(0.08), barFill: Color.black.opacity(0.22), cardFill: white.opacity(0.1),
                keyShape: .bare, rowStyle: .card)
        case (.vivid, false):
            return SippyTheme(
                scheme: scheme, isDark: false,
                paneTop: Color(hex: 0x9BF1C9), paneBottom: Color(hex: 0x7FE5B3),
                ink: indigo, dim: indigo.opacity(0.84), faint: indigo.opacity(0.55),
                accent: indigo, callFill: indigo, callGlyph: mint,
                // Green can't mean "registered" on a mint pane.
                signal: indigo, warning: Color(hex: 0x9A4A00),
                danger: Color(hex: 0xA81E2B), hangUp: Color(hex: 0xC92F36),
                controlFill: indigo.opacity(0.13), activeFill: indigo, activeGlyph: mint,
                hairline: indigo.opacity(0.12), barFill: indigo.opacity(0.1), cardFill: white.opacity(0.45),
                keyShape: .bare, rowStyle: .card)
        }
    }

    /// The look outside the main window (Settings shares a few views with
    /// it): system colors on a system background.
    static let system = SippyTheme(
        scheme: .enamel, isDark: false,
        paneTop: Color(nsColor: .windowBackgroundColor), paneBottom: Color(nsColor: .windowBackgroundColor),
        ink: .primary, dim: .secondary, faint: Color(nsColor: .tertiaryLabelColor),
        accent: .accentColor, callFill: .sippyMint, callGlyph: .sippyIndigo,
        signal: .sippyCall, warning: .orange, danger: .red, hangUp: .red,
        controlFill: Color.primary.opacity(0.06),
        activeFill: .primary, activeGlyph: Color(nsColor: .windowBackgroundColor),
        hairline: Color(nsColor: .separatorColor), barFill: Color.primary.opacity(0.06),
        cardFill: Color.primary.opacity(0.06),
        keyShape: .tile, rowStyle: .ruled)
}

// The key is spelled out: the @Entry macro needs a compiler plugin that
// ships only with Xcode (see ViewState.swift).
private struct SippyThemeKey: EnvironmentKey {
    static let defaultValue = SippyTheme.system
}

extension EnvironmentValues {
    var sippyTheme: SippyTheme {
        get { self[SippyThemeKey.self] }
        set { self[SippyThemeKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Window

/// Whether the system is in dark mode, for the "Match System" variant.
/// Read from the app rather than from the view's `colorScheme`: once a
/// window has been pinned to one appearance, its views keep reporting that
/// one even after the pin is lifted.
@MainActor
@Observable
final class SystemAppearance {
    static let shared = SystemAppearance()

    private(set) var isDark = SystemAppearance.read()
    @ObservationIgnored private var observation: NSKeyValueObservation?

    private init() {
        observation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                let dark = Self.read()
                if self.isDark != dark { self.isDark = dark }
            }
        }
    }

    private static func read() -> Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

/// Where the title bar leaves room for our own controls: its height, and
/// the horizontal span right of the traffic lights (as insets from the
/// window's edges).
struct WindowChromeMetrics: Equatable {
    var titlebarHeight: CGFloat = 28
    var leading: CGFloat = 77
    var trailing: CGFloat = 8
}

/// Sits invisibly in the main window to do what SwiftUI has no modifier
/// for: put `titlebar` beside the traffic lights, measure the title bar the
/// content draws under, and let the pane move the window.
///
/// The controls have to live in the title bar proper (an accessory), not in
/// the content underneath it: the title bar is transparent here, but it
/// still takes every click in its strip.
struct WindowChrome<Titlebar: View>: NSViewRepresentable {
    @Binding var metrics: WindowChromeMetrics
    @ViewBuilder var titlebar: Titlebar

    func makeNSView(context: Context) -> WindowChromeProbe {
        let view = WindowChromeProbe()
        view.report = { measured in
            if metrics != measured { metrics = measured }
        }
        return view
    }

    func updateNSView(_ view: WindowChromeProbe, context: Context) {
        view.host.rootView = AnyView(titlebar)
        view.apply()
    }
}

final class WindowChromeProbe: NSView {
    let host = NSHostingView(rootView: AnyView(EmptyView()))
    var report: ((WindowChromeMetrics) -> Void)?
    private let accessory = NSTitlebarAccessoryViewController()

    override init(frame: NSRect) {
        super.init(frame: frame)
        // The accessory is sized by us, not by its SwiftUI content.
        host.sizingOptions = []
        accessory.view = host
        accessory.layoutAttribute = .leading
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if let window, window !== newWindow,
           let index = window.titlebarAccessoryViewControllers.firstIndex(of: accessory) {
            window.removeTitlebarAccessoryViewController(at: index)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window, !window.titlebarAccessoryViewControllers.contains(accessory) {
            window.addTitlebarAccessoryViewController(accessory)
        }
        apply()
    }

    func apply() {
        guard let window else { return }
        window.titlebarSeparatorStyle = .none
        // One pane, no chrome: any spot without a control moves the window.
        window.isMovableByWindowBackground = true

        var measured = WindowChromeMetrics()
        measured.titlebarHeight = max(window.frame.height - window.contentLayoutRect.height, 28)
        var lightsEnd: CGFloat = 69
        if let zoom = window.standardWindowButton(.zoomButton), let bar = zoom.superview {
            lightsEnd = bar.convert(zoom.frame, to: nil).maxX
        }
        // Everything right of the traffic lights, less a margin on both ends.
        let size = NSSize(
            width: max(window.frame.width - lightsEnd - 16, 0), height: measured.titlebarHeight)
        if host.frame.size != size { host.setFrameSize(size) }
        if host.window != nil {
            let span = host.convert(host.bounds, to: nil)
            measured.leading = span.minX
            measured.trailing = window.frame.width - span.maxX
        }
        // Not during the view update that called us.
        DispatchQueue.main.async { [weak self] in self?.report?(measured) }
    }
}
