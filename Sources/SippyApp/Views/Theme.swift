import AppKit
import SwiftUI

/// Shared metrics, so the windows agree with each other instead of each view
/// picking its own numbers.
enum SippyLayout {
    /// The main window is a phone, not a document: one fixed, narrow width
    /// for the dialpad, contacts, history and the call screen. Only the
    /// height is resizable (the lists benefit from it).
    static let mainWidth: CGFloat = 320
    static let mainMinHeight: CGFloat = 520
    static let mainIdealHeight: CGFloat = 600
    /// Horizontal inset of free-standing content (dialpad, call screen).
    static let mainPadding: CGFloat = 24

    /// Every Settings tab has this width; the height follows the tab.
    static let settingsWidth: CGFloat = 460
}

extension Color {
    /// The mint of the app icon's "Signal S".
    static let sippyMint = Color(red: 0.54, green: 0.93, blue: 0.74)
    /// The app icon's background indigo.
    static let sippyIndigo = Color(red: 0.184, green: 0.169, blue: 0.475)

    /// Call green on a system background (Settings): the icon mint is too
    /// pale on white, so light mode gets a deeper shade of the same hue. The
    /// main window takes its colors from `SippyTheme` instead.
    static let sippyCall = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.54, green: 0.93, blue: 0.74, alpha: 1)
            : NSColor(srgbRed: 0.07, green: 0.58, blue: 0.39, alpha: 1)
    })
}

// MARK: - Buttons

/// Keypad key (dialpad and in-call DTMF pad), drawn the way the theme draws
/// keys: a tile, an outlined ring, or the bare numeral. All three share the
/// hover and pressed veil.
struct DialKeyStyle: ButtonStyle {
    var height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        KeyBody(configuration: configuration, height: height)
    }

    private struct KeyBody: View {
        let configuration: ButtonStyleConfiguration
        let height: CGFloat
        @Environment(\.sippyTheme) private var theme
        @ViewState private var hovering = false

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(plate)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }

        @ViewBuilder
        private var plate: some View {
            let veil = theme.veil(pressed: configuration.isPressed, hovering: hovering)
            switch theme.keyShape {
            case .tile:
                let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
                shape.fill(theme.controlFill).overlay(shape.fill(veil))
            case .ring:
                // A circle at dialpad size; the short in-call keys are
                // capsules as wide as their column.
                let round = height >= 50
                let shape = round ? AnyInsettableShape(Circle()) : AnyInsettableShape(Capsule())
                shape.fill(veil)
                    .overlay(shape.strokeBorder(theme.outline, lineWidth: 1))
                    .frame(width: round ? height : nil)
            case .bare:
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(veil)
            }
        }
    }
}

/// Round action button: the dial/answer/hang-up buttons and the in-call
/// toggles. The label is just the SF Symbol.
struct CircleButtonStyle: ButtonStyle {
    enum Kind {
        /// Start or accept a call.
        case call
        /// Decline or end a call.
        case hangUp
        /// In-call toggle that is off.
        case neutral
        /// In-call toggle that is on, like a lit key.
        case active
    }

    var kind: Kind
    var diameter: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        CircleBody(configuration: configuration, kind: kind, diameter: diameter)
    }

    private struct CircleBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        let diameter: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.sippyTheme) private var theme
        @ViewState private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: diameter * 0.38, weight: .medium))
                .foregroundStyle(glyph)
                .frame(width: diameter, height: diameter)
                .background(shape.fill(fill))
                .overlay(shape.strokeBorder(stroke, lineWidth: 1))
                // Hover/pressed feedback as a veil, so it works on any fill.
                .overlay(shape.fill(theme.veil(
                    pressed: isEnabled && configuration.isPressed, hovering: isEnabled && hovering)))
                .contentShape(shape)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }

        private var isToggle: Bool { kind == .neutral || kind == .active }

        /// The loud scheme squares its toggles off; everything else is round.
        private var shape: AnyInsettableShape {
            if isToggle, theme.usesPills {
                AnyInsettableShape(RoundedRectangle(cornerRadius: diameter * 0.33, style: .continuous))
            } else {
                AnyInsettableShape(Circle())
            }
        }

        private var outlined: Bool { theme.keyShape == .ring }

        private var fill: Color {
            guard isEnabled else { return theme.controlFill }
            switch kind {
            case .call: return theme.callFill
            case .hangUp: return theme.hangUp
            case .neutral: return outlined ? .clear : theme.controlFill
            case .active: return theme.activeFill
            }
        }

        private var stroke: Color {
            guard isEnabled else { return .clear }
            switch kind {
            case .call: return theme.callRing
            case .neutral: return outlined ? theme.outline : .clear
            case .hangUp, .active: return .clear
            }
        }

        private var glyph: Color {
            guard isEnabled else { return theme.faint }
            switch kind {
            case .call: return theme.callGlyph
            case .hangUp: return .white
            case .neutral: return theme.ink
            case .active: return theme.activeGlyph
            }
        }
    }
}

/// `AnyShape` for shapes that can also `strokeBorder`.
struct AnyInsettableShape: InsettableShape {
    private let base: any InsettableShape
    private var inset: CGFloat = 0

    init(_ base: some InsettableShape) { self.base = base }

    func path(in rect: CGRect) -> Path {
        inset == 0 ? base.path(in: rect) : pathInset(base, by: inset, in: rect)
    }

    func inset(by amount: CGFloat) -> AnyInsettableShape {
        var copy = self
        copy.inset += amount
        return copy
    }

    private func pathInset(_ shape: some InsettableShape, by amount: CGFloat, in rect: CGRect) -> Path {
        shape.inset(by: amount).path(in: rect)
    }
}

/// Wide labelled action button of the schemes that use them: icon and
/// title on a capsule, as wide as it is given.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case call, hangUp }

    var kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, kind: kind)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        @Environment(\.controlSize) private var controlSize
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.sippyTheme) private var theme
        @ViewState private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: controlSize == .small ? 12 : 15, weight: .semibold))
                .foregroundStyle(glyph)
                .frame(maxWidth: .infinity)
                .frame(height: controlSize == .small ? 32 : 52)
                .background(Capsule().fill(fill))
                .overlay(Capsule().fill(theme.veil(
                    pressed: isEnabled && configuration.isPressed, hovering: isEnabled && hovering)))
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }

        private var fill: Color {
            guard isEnabled else { return theme.controlFill }
            return kind == .call ? theme.callFill : theme.hangUp
        }

        private var glyph: Color {
            guard isEnabled else { return theme.faint }
            return kind == .call ? theme.callGlyph : .white
        }
    }
}

/// Small call button at the trailing edge of a list row (history entries,
/// contact numbers).
struct RowCallButton: View {
    @Environment(SIPEngine.self) private var engine
    @Environment(\.sippyTheme) private var theme
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "phone.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(glyph)
                .frame(width: 24, height: 24)
                .background(plate)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .disabled(engine.registration != .registered || engine.call != nil)
        .help("Call")
        .accessibilityLabel("Call")
    }

    /// On a light enamel pane the glyph is ink, like the pane's other marks;
    /// everywhere else it carries the signal color.
    private var tint: Color {
        theme.scheme == .enamel && !theme.isDark ? theme.ink : theme.signal
    }

    private var glyph: Color { theme.rowStyle == .card ? theme.callGlyph : tint }

    @ViewBuilder
    private var plate: some View {
        switch theme.rowStyle {
        case .ruled:
            Circle().fill(tint.opacity(hovering ? 0.26 : 0.15))
        case .plain:
            Circle().fill(tint.opacity(hovering ? 0.16 : 0))
                .overlay(Circle().strokeBorder(tint.opacity(0.5), lineWidth: 1))
        case .card:
            Circle().fill(theme.callFill)
                .overlay(Circle().fill(theme.veil(pressed: false, hovering: hovering)))
        }
    }
}

// MARK: - Monogram

/// Initials in a quiet disc: the face of a contact row and the focal point
/// of the call screen. Falls back to a person glyph for bare numbers.
struct Monogram: View {
    @Environment(\.sippyTheme) private var theme
    let name: String
    var diameter: CGFloat = 76
    /// The call screen's: schemes that accent it use the call colors.
    var prominent = false

    private var accented: Bool { prominent && theme.accentedMonogram }

    var body: some View {
        ZStack {
            if accented {
                Circle().fill(theme.callFill)
            } else if theme.keyShape == .ring {
                Circle().strokeBorder(theme.outline, lineWidth: 1)
            } else {
                Circle().fill(theme.controlFill)
            }
            if let initials {
                Text(initials)
                    .font(.system(size: diameter * 0.38, weight: .medium, design: .rounded))
                    .foregroundStyle(accented ? theme.callGlyph : theme.dim)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: diameter * 0.42))
                    .foregroundStyle(accented ? theme.callGlyph : theme.faint)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    private var initials: String? {
        let words = name.split(whereSeparator: { !$0.isLetter }).prefix(2)
        guard !words.isEmpty else { return nil }
        return words.compactMap(\.first).map { String($0).uppercased() }.joined()
    }
}

// MARK: - Lists

extension View {
    /// A row of the main window's lists, separated the way the theme
    /// separates rows: a hairline, nothing, or a card of its own.
    func sippyListRow() -> some View { modifier(SippyListRow()) }
}

private struct SippyListRow: ViewModifier {
    @Environment(\.sippyTheme) private var theme

    func body(content: Content) -> some View {
        content
            .listRowSeparator(theme.rowStyle == .ruled ? .visible : .hidden)
            .listRowSeparatorTint(theme.hairline)
            .listRowBackground(card)
    }

    @ViewBuilder
    private var card: some View {
        if theme.rowStyle == .card {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.cardFill)
                .padding(.vertical, 2)
        } else {
            Color.clear
        }
    }
}

/// Text button on the pane, where the system link color would be wrong.
struct PaneLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LinkBody(configuration: configuration)
    }

    private struct LinkBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.sippyTheme) private var theme

        var body: some View {
            configuration.label
                .foregroundStyle(theme.accent)
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(Rectangle())
        }
    }
}

// MARK: - Registration status

extension SIPEngine.RegistrationStatus {
    func color(in theme: SippyTheme) -> Color {
        switch self {
        case .registered: theme.signal
        case .connecting: theme.warning
        case .failed: theme.danger
        case .unconfigured: theme.faint
        case .waitingForRoute: theme.warning
        }
    }
}

/// Registration state as a dot (a spinner while connecting) plus one line of
/// text. Used by the main window's status bar or chip and the Account
/// settings.
struct RegistrationStatusLabel: View {
    @Environment(SIPEngine.self) private var engine
    @Environment(\.sippyTheme) private var theme
    var font: Font = .callout

    var body: some View {
        HStack(spacing: 7) {
            if engine.registration == .connecting {
                ProgressView().controlSize(.mini)
            } else {
                Circle().fill(engine.registration.color(in: theme)).frame(width: 8, height: 8)
            }
            Text(label)
                .font(font)
                .foregroundStyle(engine.registration == .registered ? theme.dim : theme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        // The line truncates at the narrow main width; the tooltip has it all.
        .help(label)
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        switch engine.registration {
        case .registered: "\(engine.account.username)@\(engine.account.domain)"
        case .connecting: "Connecting…"
        case .failed(let message): "Registration failed: \(message)"
        case .unconfigured: "No account configured"
        case .waitingForRoute: "Server unreachable — waiting for a route (VPN down?)"
        }
    }
}

// MARK: - Settings

/// The one layout every Settings tab uses: a grouped form at the shared
/// width and, optionally, a bar pinned underneath for the tab's action
/// (Apply, Import…, Reset) with a note or status on its left.
///
/// Explanations go in section footers, never in rows. Tabs that fit are
/// sized to their content (`height: nil`) and the window follows; long ones
/// get a fixed height and scroll. `height: nil` disables scrolling, so a tab
/// whose content can grow without limit must switch to a height before it
/// outgrows the screen.
///
/// `form: false` takes the content as is, inset like a form section — for
/// the one thing a grouped form can't hold, a drag-reorderable list.
struct SettingsPane<Content: View, Bar: View>: View {
    var height: CGFloat?
    var form = true
    @ViewBuilder var content: Content
    @ViewBuilder var bar: Bar

    var body: some View {
        VStack(spacing: 0) {
            if form {
                Form { content }
                    .formStyle(.grouped)
                    .scrollDisabled(height == nil)
                    .fixedSize(horizontal: false, vertical: height == nil)
            } else {
                content.padding(20)
            }
            if Bar.self != EmptyView.self {
                Divider()
                HStack(spacing: 12) { bar }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
        }
        .frame(width: SippyLayout.settingsWidth, height: height)
    }
}

extension SettingsPane where Bar == EmptyView {
    init(height: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.init(height: height, content: content, bar: { EmptyView() })
    }
}

/// Explanation under a settings section (use as the section's footer).
struct SettingsFootnote<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) { content }
            .font(.callout)
            .foregroundStyle(.secondary)
            // Forms right-align multi-line text by default.
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SettingsFootnote where Content == Text {
    init(_ text: String) {
        self.init { Text(text) }
    }
}

/// Secondary note on the left of a `SettingsPane` bar.
struct SettingsBarNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
