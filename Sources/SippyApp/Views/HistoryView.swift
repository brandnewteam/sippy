import SwiftUI
import SippyCore

struct HistoryView: View {
    @Environment(SIPEngine.self) private var engine
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if store.records.isEmpty {
                ContentUnavailableView(
                    "No Calls Yet", systemImage: "clock.arrow.circlepath",
                    description: Text("Placed and received calls appear here."))
            } else {
                List {
                    Section {
                        ForEach(store.records) { record in
                            HistoryRow(record: record)
                        }
                    } footer: {
                        HStack {
                            Spacer()
                            Button("Clear History") { store.clearHistory() }
                                .buttonStyle(PaneLinkButtonStyle())
                                .font(.caption)
                        }
                    }
                }
                .listStyle(.inset)
                // The pane shows through; the list brings no background.
                .scrollContentBackground(.hidden)
            }
        }
    }
}

struct HistoryRow: View {
    @Environment(SIPEngine.self) private var engine
    @Environment(AppStore.self) private var store
    @Environment(\.sippyTheme) private var theme
    let record: CallRecord

    private var isMissed: Bool { record.outcome == .missed }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: record.direction == .incoming ? "phone.arrow.down.left" : "phone.arrow.up.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isMissed ? theme.danger : theme.dim)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.displayName)
                    .foregroundStyle(isMissed ? theme.danger : theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(Self.shortDate(record.date))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
                .help(record.date.formatted(date: .complete, time: .shortened))
            RowCallButton {
                // Redial exactly what was dialed before — any prefix is
                // already baked into the stored number.
                engine.dial(record.number, origin: .internalContact)
            }
        }
        .padding(.vertical, 2)
        .sippyListRow()
        .contextMenu {
            Button("Delete", role: .destructive) { store.deleteRecord(record.id) }
        }
    }

    /// Number and outcome; just the outcome when the caller has no name and
    /// the title already is the number.
    private var subtitle: String {
        record.displayName == record.number ? detail : "\(record.number) · \(detail)"
    }

    /// Compact date for the narrow window, the way Phone and Mail do it:
    /// time today, then "Yesterday", the weekday within a week, else the date.
    static func shortDate(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days == 1 { return "Yesterday" }
        if (2..<7).contains(days) { return date.formatted(.dateTime.weekday(.wide)) }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private var detail: String {
        switch record.outcome {
        case .answered:
            let minutes = record.durationSeconds / 60
            let seconds = record.durationSeconds % 60
            return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
        case .missed: return "missed"
        case .declined: return "declined"
        case .failed: return "failed"
        case .unanswered: return "no answer"
        }
    }
}
