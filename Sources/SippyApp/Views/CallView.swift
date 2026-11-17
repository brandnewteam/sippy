import SwiftUI
import SippyCore

struct CallView: View {
    @Environment(SIPEngine.self) private var engine
    @Environment(\.sippyTheme) private var theme
    @ViewState private var showDTMFPad = false
    @ViewState private var showStats = false

    var body: some View {
        guard let call = engine.call else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(spacing: 0) {
                Spacer(minLength: 16)
                header(call)
                Spacer(minLength: 16)

                VStack(spacing: 14) {
                    if showStats, call.phase != .ringingIncoming {
                        CallStatsPanel()
                    }
                    if showDTMFPad, call.phase != .ringingIncoming {
                        DTMFPad { engine.sendDTMF($0) }
                    }
                    switch call.phase {
                    case .ringingIncoming:
                        incomingControls
                    default:
                        inCallControls(call)
                    }
                }
            }
            // Controls stay anchored to the bottom, like on a phone; only
            // the space around the header stretches with the window.
            .padding(.bottom, 24)
            .padding(.horizontal, SippyLayout.mainPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }

    /// Room for the header's showpiece (monogram, signal line): gone while
    /// the stats or the keypad need the space.
    private func isRoomy(_ call: SIPEngine.CallInfo) -> Bool {
        !(showStats || showDTMFPad) || call.phase == .ringingIncoming
    }

    @ViewBuilder
    private func header(_ call: SIPEngine.CallInfo) -> some View {
        if theme.timerHero {
            timerHeader(call)
        } else {
            VStack(spacing: 6) {
                if isRoomy(call) {
                    Monogram(name: call.remoteDisplay, prominent: true)
                        .padding(.bottom, 8)
                }
                names(call)
                statusLine(call)
                    .padding(.top, 2)
            }
        }
    }

    private func names(_ call: SIPEngine.CallInfo) -> some View {
        VStack(spacing: 6) {
            Text(call.remoteDisplay)
                .font(.title2.weight(theme.usesPills ? .semibold : .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(call.remoteURI)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// The header led by what the call is doing: the running timer in the
    /// accent once connected, the state in words until then, over a signal
    /// line.
    private func timerHeader(_ call: SIPEngine.CallInfo) -> some View {
        VStack(spacing: 0) {
            names(call)
            Group {
                if call.phase == .active, let start = call.startedAt {
                    Text(start, style: .timer)
                        .font(.system(size: 44, weight: .light, design: .rounded))
                        .monospacedDigit()
                } else {
                    statusText(call)
                        .font(.system(size: 22, weight: .light, design: .rounded))
                }
            }
            .foregroundStyle(theme.accent)
            .padding(.top, 12)
            if isRoomy(call) {
                SignalLine()
                    .stroke(theme.signal, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: 232, height: 40)
                    .padding(.top, 10)
                    .accessibilityHidden(true)
            }
            if call.phase == .active, let codec = call.codec {
                Text(codec)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
    }

    /// The call's state in words; nil-timer `active` falls back to the name
    /// of the state so the line is never empty.
    private func statusText(_ call: SIPEngine.CallInfo) -> Text {
        switch call.phase {
        case .ringingIncoming: Text("Incoming call…")
        case .ringingOutgoing: Text("Calling…")
        case .ending: Text("Ending…")
        case .held: Text("On hold")
        case .heldByRemote: Text("Held by remote")
        case .active: Text("Connected")
        }
    }

    @ViewBuilder
    private func statusLine(_ call: SIPEngine.CallInfo) -> some View {
        HStack(spacing: 6) {
            if call.phase == .active {
                if let start = call.startedAt {
                    Text(start, style: .timer).monospacedDigit()
                }
                if let codec = call.codec {
                    Text("· \(codec)")
                }
            } else {
                statusText(call)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var incomingControls: some View {
        if theme.usesPills {
            HStack(spacing: 12) {
                Button { engine.decline() } label: {
                    Label("Decline", systemImage: "phone.down.fill")
                }
                .buttonStyle(PillButtonStyle(kind: .hangUp))
                Button { engine.answer() } label: {
                    Label("Answer", systemImage: "phone.fill")
                }
                .buttonStyle(PillButtonStyle(kind: .call))
            }
        } else {
            roundIncomingControls
        }
    }

    private var roundIncomingControls: some View {
        HStack(spacing: 56) {
            RoundActionButton(symbol: "phone.down.fill", kind: .hangUp, label: "Decline", diameter: 58) {
                engine.decline()
            }
            RoundActionButton(symbol: "phone.fill", kind: .call, label: "Answer", diameter: 58) {
                engine.answer()
            }
        }
    }

    /// The four toggles on one row, the hang-up button on its own below:
    /// the one action that ends things shouldn't sit among the toggles.
    private func inCallControls(_ call: SIPEngine.CallInfo) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 0) {
                RoundActionButton(
                    symbol: call.isMuted ? "mic.slash.fill" : "mic.fill",
                    kind: call.isMuted ? .active : .neutral,
                    label: call.isMuted ? "Unmute" : "Mute"
                ) { engine.toggleMute() }
                Spacer(minLength: 0)
                RoundActionButton(
                    symbol: call.phase == .held ? "play.fill" : "pause.fill",
                    kind: call.phase == .held ? .active : .neutral,
                    label: call.phase == .held ? "Resume" : "Hold"
                ) { engine.toggleHold() }
                Spacer(minLength: 0)
                RoundActionButton(
                    symbol: "circle.grid.3x3.fill",
                    kind: showDTMFPad ? .active : .neutral,
                    label: "Keypad"
                ) { showDTMFPad.toggle() }
                Spacer(minLength: 0)
                RoundActionButton(
                    symbol: "chart.xyaxis.line",
                    kind: showStats ? .active : .neutral,
                    label: "Stats"
                ) { showStats.toggle() }
            }

            if theme.usesPills {
                Button { engine.hangUp() } label: {
                    Label("End Call", systemImage: "phone.down.fill")
                }
                .buttonStyle(PillButtonStyle(kind: .hangUp))
            } else {
                RoundActionButton(symbol: "phone.down.fill", kind: .hangUp, label: "End", diameter: 58) {
                    engine.hangUp()
                }
            }
        }
    }
}

struct RoundActionButton: View {
    let symbol: String
    let kind: CircleButtonStyle.Kind
    let label: String
    var diameter: CGFloat = 52
    let action: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            Button(action: action) {
                Image(systemName: symbol)
            }
            .buttonStyle(CircleButtonStyle(kind: kind, diameter: diameter))
            .accessibilityLabel(label)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

/// A resting line with two bursts of signal: the app icon's waveform, laid
/// flat. Drawn on a 232 × 40 grid and scaled to the frame.
struct SignalLine: Shape {
    private static let points: [(x: CGFloat, y: CGFloat)] = [
        (2, 20), (48, 20), (55, 7), (64, 33), (72, 14), (78, 23), (83, 20),
        (133, 20), (140, 5), (150, 35), (158, 14), (164, 23), (169, 20), (230, 20),
    ]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, point) in Self.points.enumerated() {
            let scaled = CGPoint(
                x: rect.minX + point.x / 232 * rect.width,
                y: rect.minY + point.y / 40 * rect.height)
            if index == 0 { path.move(to: scaled) } else { path.addLine(to: scaled) }
        }
        return path
    }
}

struct DTMFPad: View {
    let send: (Character) -> Void
    private static let rows: [[Character]] = [
        ["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["*", "0", "#"],
    ]

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 8) {
            ForEach(Self.rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { digit in
                        Button {
                            send(digit)
                        } label: {
                            if digit == "*" {
                                Image(systemName: "asterisk")
                                    .font(.system(size: 13, weight: .medium))
                            } else {
                                Text(String(digit))
                                    .font(.system(size: 18, design: .rounded))
                            }
                        }
                        .buttonStyle(DialKeyStyle(height: 36))
                        .accessibilityLabel(String(digit))
                    }
                }
            }
        }
    }
}
