import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Ringtones: pick the ring sound (bundled or imported), preview
/// it, import custom files, and route ringing to a specific output device.
struct RingtoneSettingsTab: View {
    @Environment(SIPEngine.self) private var engine
    @Environment(RingtoneLibrary.self) private var ringtones

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section("Ringtone") {
                    ForEach(ringtones.ringtones) { tone in
                        row(for: tone)
                    }
                }
            }
            Divider()
            VStack(spacing: 8) {
                Picker("Ring on", selection: Binding(
                    get: { engine.selectedRingerDevice ?? "" },
                    set: { engine.setRingerDevice($0) }
                )) {
                    ForEach(engine.ringerDevices, id: \.self) { Text($0).tag($0) }
                }
                .help("Ring can go to speakers while calls use the headset.")
                HStack {
                    Text("Imported files are copied into Sippy's library.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Import…") { importRingtone() }
                }
            }
            .padding(10)
        }
        .onAppear { engine.refreshRingerDevices() }
    }

    private var selectedFileName: String? {
        ringtones.ringtone(named: engine.account.ringtone)?.fileName
    }

    private func row(for tone: RingtoneLibrary.Ringtone) -> some View {
        HStack(spacing: 8) {
            Image(systemName: tone.fileName == selectedFileName ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(tone.fileName == selectedFileName ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(tone.displayName)
                if !tone.isBuiltIn {
                    Text("Imported").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                ringtones.togglePreview(tone)
            } label: {
                Image(systemName: ringtones.previewingID == tone.id ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderless)
            .help("Preview")
            if !tone.isBuiltIn {
                Button {
                    delete(tone)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete imported ringtone")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { select(tone) }
    }

    private func select(_ tone: RingtoneLibrary.Ringtone) {
        engine.setRingtone(fileName: tone.fileName, path: tone.url.path)
    }

    private func delete(_ tone: RingtoneLibrary.Ringtone) {
        let wasSelected = tone.fileName == selectedFileName
        ringtones.delete(tone)
        if wasSelected, let fallback = ringtones.ringtone(named: nil) {
            engine.setRingtone(fileName: fallback.fileName, path: fallback.url.path)
        }
    }

    private func importRingtone() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = RingtoneLibrary.importableExtensions
            .compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            _ = try? ringtones.importRingtone(from: url)
        }
    }
}
