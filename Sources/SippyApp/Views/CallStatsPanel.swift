import SwiftUI
import SippyCore

/// Live traffic inspector shown inside the call view: negotiated codec,
/// encryption, ICE, and per-second bandwidth / jitter / RTT / loss with
/// sparklines over the whole call.
struct CallStatsPanel: View {
    @Environment(SIPEngine.self) private var engine
    @Environment(\.sippyTheme) private var theme

    var body: some View {
        let history = engine.statsHistory
        VStack(alignment: .leading, spacing: 8) {
            if let last = history.last {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                    GridRow {
                        statCell("Codec", engine.call?.codec ?? "—")
                        statCell("Encryption", last.encryption)
                        statCell("ICE", last.iceState)
                    }
                    GridRow {
                        statCell("RTT", String(format: "%.0f ms", last.rttMs))
                        statCell("Jitter ↓", String(format: "%.1f ms", last.downloadJitterMs))
                        statCell("Loss ↓/↑", String(format: "%.1f / %.1f %%", last.downloadLossPct, last.uploadLossPct))
                    }
                }

                sparklineRow(
                    title: "Bandwidth",
                    value: String(format: "↓ %.0f  ↑ %.0f kbit/s", last.downloadKbps, last.uploadKbps),
                    series: [
                        (history.map { $0.downloadKbps }, theme.accent),
                        (history.map { $0.uploadKbps }, theme.dim),
                    ])
                sparklineRow(
                    title: "Jitter",
                    value: String(format: "%.1f ms", last.downloadJitterMs),
                    series: [(history.map { $0.downloadJitterMs }, theme.warning)])
                sparklineRow(
                    title: "Loss",
                    value: String(format: "%.1f %%", last.downloadLossPct),
                    series: [(history.map { $0.downloadLossPct }, theme.danger)])
            } else {
                Text("Waiting for media statistics…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.controlFill))
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.monospacedDigit()).lineLimit(1)
        }
        .frame(minWidth: 70, alignment: .leading)
    }

    private func sparklineRow(
        title: String, value: String, series: [([Float], Color)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            ZStack {
                ForEach(Array(series.enumerated()), id: \.offset) { _, line in
                    Sparkline(values: line.0, color: line.1)
                }
            }
            .frame(height: 22)
        }
    }
}

/// Tiny line graph; scales to the series' own max (with a sane floor so a
/// flat zero line doesn't fill the frame).
struct Sparkline: View {
    let values: [Float]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let maxValue = max(values.max() ?? 1, 0.001)
            let count = max(values.count, 2)
            Path { path in
                for (index, value) in values.enumerated() {
                    let x = geo.size.width * CGFloat(index) / CGFloat(count - 1)
                    let y = geo.size.height * (1 - CGFloat(min(value, maxValue) / maxValue) * 0.9)
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color.opacity(0.8), lineWidth: 1.2)
        }
    }
}
