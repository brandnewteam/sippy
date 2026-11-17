import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Ringtones: pick the ring sound (bundled or imported), preview
/// it, import custom files, and route ringing to a specific output device.
struct RingtoneSettingsTab: View {
    @Environment(SIPEngine.self) private var engine
    @Environment(RingtoneLibrary.self) private var ringtones

    var body: some View {
        SettingsPane {
            Section("Ringtone") {
                ForEach(ringtones.ringtones) { tone in
                    row(for: tone)
                }
            }
            Section {
                Picker("Ring on", selection: Binding(
                    get: { engine.selectedRingerDevice ?? "" },
                    set: { engine.setRingerDevice($0) }
                )) {
                    ForEach(engine.ringerDevices, id: \.self) { Text($0).tag($0) }
                }
            } footer: {
                SettingsFootnote("The ring can go to the speakers while calls use the headset.")
            }
        } bar: {
            SettingsBarNote("Imported files are copied into Sippy's library.")
            Button("Import…") { importRingtone() }
        }
        .onAppear { engine.refreshRingerDevices() }
    }

    private var selectedFileName: String? {
        ringtones.ringtone(named: engine.account.ringtone)?.fileName
    }

    private func row(for tone: RingtoneLibrary.Ringtone) -> some View {
        let isSelected = tone.fileName == selectedFileName
        return HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .opacity(isSelected ? 1 : 0)
                .frame(width: 16)
            Text(tone.displayName)
            if !tone.isBuiltIn {
                Text("Imported").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !tone.isBuiltIn {
                Button {
                    delete(tone)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Delete imported ringtone")
            }
            Button {
                ringtones.togglePreview(tone)
            } label: {
                Image(systemName: ringtones.previewingID == tone.id ? "stop.fill" : "play.fill")
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Preview")
        }
        .contentShape(Rectangle())
        .onTapGesture { select(tone) }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
