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
                                .buttonStyle(.link)
                                .font(.caption)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

struct HistoryRow: View {
    @Environment(SIPEngine.self) private var engine
    @Environment(AppStore.self) private var store
    let record: CallRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: record.direction == .incoming ? "phone.arrow.down.left" : "phone.arrow.up.right")
                .foregroundStyle(record.outcome == .missed ? .red : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(record.displayName)
                    .foregroundStyle(record.outcome == .missed ? .red : .primary)
                HStack(spacing: 4) {
                    Text(record.number).font(.caption).foregroundStyle(.secondary)
                    Text("· \(detail)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(record.date, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                // Redial exactly what was dialed before — any prefix is
                // already baked into the stored number.
                engine.dial(record.number, origin: .internalContact)
            } label: {
                Image(systemName: "phone.fill").foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .disabled(engine.registration != .registered || engine.call != nil)
        }
        .contextMenu {
            Button("Delete", role: .destructive) { store.deleteRecord(record.id) }
        }
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
