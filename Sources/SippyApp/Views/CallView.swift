import SwiftUI
import SippyCore

struct CallView: View {
    @Environment(SIPEngine.self) private var engine
    @ViewState private var showDTMFPad = false
    @ViewState private var showStats = false

    var body: some View {
        guard let call = engine.call else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(spacing: 16) {
                Spacer(minLength: 12)
                Text(call.remoteDisplay)
                    .font(.title2)
                Text(call.remoteURI)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                statusLine(call)

                Spacer()

                if showStats, call.phase != .ringingIncoming {
                    CallStatsPanel()
                }

                if showDTMFPad {
                    DTMFPad { engine.sendDTMF($0) }
                }

                switch call.phase {
                case .ringingIncoming:
                    incomingControls
                default:
                    inCallControls(call)
                }
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 20)
        )
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
                    Text("· \(codec)").foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
    }

    private var incomingControls: some View {
        HStack(spacing: 40) {
            RoundActionButton(symbol: "phone.down.fill", tint: .red, label: "Decline") {
                engine.decline()
            }
            RoundActionButton(symbol: "phone.fill", tint: .green, label: "Answer") {
                engine.answer()
            }
        }
    }

    @ViewBuilder
    private func inCallControls(_ call: SIPEngine.CallInfo) -> some View {
        HStack(spacing: 16) {
            RoundActionButton(
                symbol: call.isMuted ? "mic.slash.fill" : "mic.fill",
                tint: call.isMuted ? .orange : .secondary,
                label: "Mute"
            ) { engine.toggleMute() }

            RoundActionButton(
                symbol: "pause.fill",
                tint: call.phase == .held ? .orange : .secondary,
                label: call.phase == .held ? "Resume" : "Hold"
            ) { engine.toggleHold() }

            RoundActionButton(
                symbol: "circle.grid.3x3.fill",
                tint: showDTMFPad ? .accentColor : .secondary,
                label: "Keypad"
            ) { showDTMFPad.toggle() }

            RoundActionButton(
                symbol: "chart.xyaxis.line",
                tint: showStats ? .accentColor : .secondary,
                label: "Stats"
            ) { showStats.toggle() }

            RoundActionButton(symbol: "phone.down.fill", tint: .red, label: "End") {
                engine.hangUp()
            }
        }
    }
}

struct RoundActionButton: View {
    let symbol: String
    let tint: Color
    let label: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(tint))
            }
            .buttonStyle(.plain)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct DTMFPad: View {
    let send: (Character) -> Void
    private static let digits: [Character] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(48), spacing: 10), count: 3), spacing: 8) {
            ForEach(Self.digits, id: \.self) { digit in
                Button(String(digit)) { send(digit) }
                    .font(.system(size: 16, design: .monospaced))
                    .frame(width: 48, height: 34)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
                    .buttonStyle(.plain)
            }
        }
    }
}
