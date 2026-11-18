import AppKit
import SwiftUI
import SippyCore

/// Debug window: live SIP message capture with filtering, a raw-message
/// detail pane, a codec-negotiation summary of the latest SDP offer/answer,
/// and plain-text export for bug reports.
struct SIPLogView: View {
    @Environment(SIPEngine.self) private var engine

    @ViewState private var filter = ""
    @ViewState private var selectedID: UUID?
    @ViewState private var showNegotiation = true

    private var filteredEntries: [SIPTraceEntry] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return engine.sipTrace }
        return engine.sipTrace.filter {
            $0.raw.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if engine.sipTrace.isEmpty {
                emptyState
            } else {
                // HSplitView ignores idealWidth and splits evenly; the
                // priority hands all spare width to the message, so the list
                // opens at its minimum and the divider still drags wider.
                HSplitView {
                    entryList
                        .frame(minWidth: 200, maxWidth: 420)
                    detailPane
                        .frame(minWidth: 320, maxWidth: .infinity)
                        .layoutPriority(1)
                }
            }
            if showNegotiation {
                Divider()
                CodecNegotiationSummary(trace: engine.sipTrace, activeCodec: engine.call?.codec)
            }
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Toggle("Capture", isOn: Binding(
                get: { engine.sipTraceEnabled },
                set: { engine.setSIPTraceEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            TextField("Filter (method, number, header…)", text: $filter)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)

            Spacer()

            Toggle(isOn: $showNegotiation) {
                Image(systemName: "waveform.badge.magnifyingglass")
            }
            .toggleStyle(.button)
            .help("Show codec negotiation summary")

            Button("Clear") { engine.clearSIPTrace(); selectedID = nil }
                .disabled(engine.sipTrace.isEmpty)
            Button("Export…") { exportTrace() }
                .disabled(engine.sipTrace.isEmpty)
        }
        .padding(10)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "list.bullet.rectangle")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(engine.sipTraceEnabled
                ? "Waiting for SIP traffic…"
                : "Turn on Capture to record SIP messages.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var entryList: some View {
        List(filteredEntries, selection: $selectedID) { entry in
            HStack(spacing: 6) {
                Image(systemName: entry.direction == .sent ? "arrow.up.right" : "arrow.down.left")
                    .font(.caption2)
                    .foregroundStyle(entry.direction == .sent ? Color.green : Color.blue)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Text(entry.label)
                            .font(.callout.weight(entry.isRequest ? .semibold : .regular))
                            .lineLimit(1)
                        if entry.sdp != nil {
                            Text("SDP")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 4)
                                .background(Capsule().fill(.orange.opacity(0.25)))
                        }
                    }
                    Text(entry.date, format: .dateTime.hour().minute().second(.twoDigits))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .tag(entry.id)
        }
        .listStyle(.inset)
    }

    private var detailPane: some View {
        Group {
            if let entry = filteredEntries.first(where: { $0.id == selectedID })
                ?? engine.sipTrace.first(where: { $0.id == selectedID }) {
                ScrollView([.vertical, .horizontal]) {
                    Text(entry.raw)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
            } else {
                Text("Select a message")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func exportTrace() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "sippy-sip-trace.txt"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? engine.sipTraceExportText().write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Offered vs. answered audio codecs from the latest SDP exchange in the
/// trace, so a codec-negotiation problem is visible at a glance.
struct CodecNegotiationSummary: View {
    let trace: [SIPTraceEntry]
    let activeCodec: String?

    private var lastSent: SIPTraceEntry? {
        trace.last { $0.direction == .sent && $0.sdp != nil }
    }
    private var lastReceived: SIPTraceEntry? {
        trace.last { $0.direction == .received && $0.sdp != nil }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            column(title: "We offered", entry: lastSent)
            column(title: "Remote answered/offered", entry: lastReceived)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
    }

    private func column(title: String, entry: SIPTraceEntry?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let sdp = entry?.sdp {
                ForEach(Array(sdp.codecs.prefix(8).enumerated()), id: \.offset) { _, codec in
                    HStack(spacing: 4) {
                        Text(codec.name)
                            .font(.caption.monospaced())
                            .foregroundStyle(isActive(codec) ? Color.green : Color.primary)
                        if let fmtp = codec.fmtp {
                            Text(fmtp)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
                if sdp.codecs.count > 8 {
                    Text("+\(sdp.codecs.count - 8) more").font(.caption2).foregroundStyle(.tertiary)
                }
            } else {
                Text("No SDP captured yet").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    /// Highlights the codec the current call actually uses, e.g. "G729/8000"
    /// against SDP name "G729/8000" (case-insensitive, channels ignored).
    private func isActive(_ codec: SDPAudioDescription.Codec) -> Bool {
        guard let activeCodec else { return false }
        return codec.name.lowercased().hasPrefix(activeCodec.lowercased())
    }
}
