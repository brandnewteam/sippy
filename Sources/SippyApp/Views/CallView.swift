import SwiftUI
import SippyCore

struct CallView: View {
    @Environment(SIPEngine.self) private var engine
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

    private func header(_ call: SIPEngine.CallInfo) -> some View {
        VStack(spacing: 6) {
            if !(showStats || showDTMFPad) || call.phase == .ringingIncoming {
                Monogram(name: call.remoteDisplay)
                    .padding(.bottom, 8)
            }
            Text(call.remoteDisplay)
                .font(.title2.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(call.remoteURI)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            statusLine(call)
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func statusLine(_ call: SIPEngine.CallInfo) -> some View {
        HStack(spacing: 6) {
            switch call.phase {
            case .ringingIncoming: Text("Incoming call…")
            case .ringingOutgoing: Text("Calling…")
            case .ending: Text("Ending…")
            case .held: Text("On hold")
            case .heldByRemote: Text("Held by remote")
            case .active:
                if let start = call.startedAt {
                    Text(start, style: .timer).monospacedDigit()
                }
                if let codec = call.codec {
                    Text("· \(codec)")
                }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var incomingControls: some View {
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

            RoundActionButton(symbol: "phone.down.fill", kind: .hangUp, label: "End", diameter: 58) {
                engine.hangUp()
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
