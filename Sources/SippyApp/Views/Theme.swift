import AppKit
import SwiftUI

/// Shared metrics, so the windows agree with each other instead of each view
/// picking its own numbers.
enum SippyLayout {
    /// The main window is a phone, not a document: one fixed, narrow width
    /// for the dialpad, contacts, history and the call screen. Only the
    /// height is resizable (the lists benefit from it).
    static let mainWidth: CGFloat = 320
    static let mainMinHeight: CGFloat = 500
    static let mainIdealHeight: CGFloat = 560
    /// Horizontal inset of free-standing content (dialpad, call screen).
    static let mainPadding: CGFloat = 24

    /// Every Settings tab has this width; the height follows the tab.
    static let settingsWidth: CGFloat = 460
}

extension Color {
    /// The mint of the app icon's "Signal S". Fill for the primary call
    /// actions (dial, answer) — paired with `sippyIndigo` for the glyph, the
    /// icon's own two colors.
    static let sippyMint = Color(red: 0.54, green: 0.93, blue: 0.74)
    /// The app icon's background indigo.
    static let sippyIndigo = Color(red: 0.184, green: 0.169, blue: 0.475)

    /// Call green for glyphs that sit directly on the window background
    /// (row call buttons, status dot): the icon mint is too pale on white,
    /// so light mode gets a deeper shade of the same hue.
    static let sippyCall = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.54, green: 0.93, blue: 0.74, alpha: 1)
            : NSColor(srgbRed: 0.07, green: 0.58, blue: 0.39, alpha: 1)
    })

    /// Neutral control fill that works on any background in both
    /// appearances; the levels are rest / hover / pressed.
    static func sippyControlFill(pressed: Bool = false, hovering: Bool = false) -> Color {
        Color.primary.opacity(pressed ? 0.16 : hovering ? 0.095 : 0.06)
    }
}

// MARK: - Buttons

/// Keypad key (dialpad and in-call DTMF pad): a soft rounded tile with
/// hover and pressed feedback.
struct DialKeyStyle: ButtonStyle {
    var height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        KeyBody(configuration: configuration, height: height)
    }

    private struct KeyBody: View {
        let configuration: ButtonStyleConfiguration
        let height: CGFloat
        @ViewState private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            configuration.label
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(shape.fill(Color.sippyControlFill(
                    pressed: configuration.isPressed, hovering: hovering)))
                .contentShape(shape)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

/// Round action button: the dial/answer/hang-up buttons and the in-call
/// toggles. The label is just the SF Symbol.
struct CircleButtonStyle: ButtonStyle {
    enum Kind {
        /// Start or accept a call: icon mint with the icon indigo glyph.
        case call
        /// Decline or end a call.
        case hangUp
        /// In-call toggle that is off: quiet neutral fill.
        case neutral
        /// In-call toggle that is on: inverted, like a lit key.
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
        @ViewState private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: diameter * 0.38, weight: .medium))
                .foregroundStyle(glyph)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(fill))
                // Hover/pressed feedback as a veil, so it works on any fill.
                .overlay(Circle().fill(Color.primary.opacity(
                    !isEnabled ? 0 : configuration.isPressed ? 0.16 : hovering ? 0.06 : 0)))
                .contentShape(Circle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }

        private var fill: AnyShapeStyle {
            guard isEnabled else { return AnyShapeStyle(Color.sippyControlFill()) }
            switch kind {
            case .call: return AnyShapeStyle(Color.sippyMint)
            case .hangUp: return AnyShapeStyle(Color.red)
            case .neutral: return AnyShapeStyle(Color.sippyControlFill())
            case .active: return AnyShapeStyle(Color.primary)
            }
        }

        private var glyph: AnyShapeStyle {
            guard isEnabled else { return AnyShapeStyle(.tertiary) }
            switch kind {
            case .call: return AnyShapeStyle(Color.sippyIndigo)
            case .hangUp: return AnyShapeStyle(Color.white)
            case .neutral: return AnyShapeStyle(.primary)
            case .active: return AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
            }
        }
    }
}

/// Small call button at the trailing edge of a list row (history entries,
/// contact numbers).
struct RowCallButton: View {
    @Environment(SIPEngine.self) private var engine
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "phone.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.sippyCall)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.sippyCall.opacity(hovering ? 0.22 : 0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .disabled(engine.registration != .registered || engine.call != nil)
        .help("Call")
        .accessibilityLabel("Call")
    }
}

// MARK: - Monogram

/// Initials in a quiet disc: the face of a contact row and the focal point
/// of the call screen. Falls back to a person glyph for bare numbers.
struct Monogram: View {
    let name: String
    var diameter: CGFloat = 76

    var body: some View {
        ZStack {
            Circle().fill(Color.sippyControlFill())
            if let initials {
                Text(initials)
                    .font(.system(size: diameter * 0.38, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: diameter * 0.42))
                    .foregroundStyle(.tertiary)
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

// MARK: - Registration status

extension SIPEngine.RegistrationStatus {
    var color: Color {
        switch self {
        case .registered: .sippyCall
        case .connecting: .yellow
        case .failed: .red
        case .unconfigured: .gray
        case .waitingForRoute: .orange
        }
    }
}

/// Registration state as a dot (a spinner while connecting) plus one line of
/// text. Used by the main window's status bar and the Account settings.
struct RegistrationStatusLabel: View {
    @Environment(SIPEngine.self) private var engine

    var body: some View {
        HStack(spacing: 7) {
            if engine.registration == .connecting {
                ProgressView().controlSize(.mini)
            } else {
                Circle().fill(engine.registration.color).frame(width: 8, height: 8)
            }
            Text(label)
                .font(.callout)
                .foregroundStyle(engine.registration == .registered ? .secondary : .primary)
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
