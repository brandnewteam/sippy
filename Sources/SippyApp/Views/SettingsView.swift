import SwiftUI
import SippyCore

struct SettingsView: View {
    @Environment(SIPEngine.self) private var engine
    @Environment(RingtoneLibrary.self) private var ringtones

    @State private var domain = ""
    @State private var username = ""
    @State private var password = ""
    @State private var transport: AccountConfig.Transport = .udp
    @State private var outsidePrefix = ""
    @State private var internationalPrefix = ""
    @State private var natRewrite = true
    @State private var stunServer = ""
    @State private var iceEnabled = false
    @State private var loaded = false

    var body: some View {
        TabView {
            accountTab
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            audioTab
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }
            codecsTab
                .tabItem { Label("Codecs", systemImage: "waveform") }
            RingtoneSettingsTab()
                .tabItem { Label("Ringtones", systemImage: "bell") }
        }
        .frame(width: 440, height: 520)
        .onAppear(perform: loadOnce)
        .onDisappear { ringtones.stopPreview() }
    }

    private var accountTab: some View {
        Form {
            Section("SIP Account") {
                TextField("Domain", text: $domain, prompt: Text("pbx.example.com"))
                TextField("Username", text: $username)
                SecureField("Password", text: $password)
                Picker("Transport", selection: $transport) {
                    ForEach(AccountConfig.Transport.allCases, id: \.self) {
                        Text($0.rawValue.uppercased()).tag($0)
                    }
                }
            }
            Section("Dialing") {
                TextField("Outside line prefix", text: $outsidePrefix, prompt: Text("e.g. 0 or 0*4"))
                TextField("Replace leading + with", text: $internationalPrefix, prompt: Text("e.g. 00 (empty keeps +)"))
                Text("The prefix applies to numbers from links and system contacts. The dialpad and Sippy contacts dial verbatim.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("NAT traversal") {
                Toggle("Update IP address from server replies", isOn: $natRewrite)
                TextField("STUN server", text: $stunServer, prompt: Text("stun.example.com (optional)"))
                Toggle("Use ICE", isOn: $iceEnabled)
                    .disabled(stunServer.trimmingCharacters(in: .whitespaces).isEmpty)
                Text("Leave as-is when the PBX rewrites addresses server-side (Kalliope can).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Apply") { apply() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .padding(.bottom, 8)
    }

    private var audioTab: some View {
        @Bindable var engine = engine
        return Form {
            Picker("Microphone", selection: Binding(
                get: { engine.selectedInputID ?? "" },
                set: { engine.selectInputDevice(id: $0) }
            )) {
                ForEach(engine.inputDevices) { Text($0.name).tag($0.id) }
            }
            Picker("Output", selection: Binding(
                get: { engine.selectedOutputID ?? "" },
                set: { engine.selectOutputDevice(id: $0) }
            )) {
                ForEach(engine.outputDevices) { Text($0.name).tag($0.id) }
            }
        }
        .formStyle(.grouped)
        .onAppear { engine.refreshAudioDevices() }
    }

    /// Order = priority; changes apply immediately (they only take effect on
    /// the next call anyway).
    private var codecsTab: some View {
        VStack(spacing: 0) {
            List {
                ForEach(engine.codecPreferences) { pref in
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(
                            get: { pref.enabled },
                            set: { setEnabled($0, for: pref.id) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(pref.displayName)
                            Text(pref.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                    }
                    .opacity(pref.enabled ? 1 : 0.5)
                }
                .onMove { from, to in
                    var codecs = engine.codecPreferences
                    codecs.move(fromOffsets: from, toOffset: to)
                    engine.setCodecPreferences(codecs)
                }
            }
            Divider()
            HStack {
                Text("Drag to set priority. First enabled codec is offered first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset to Defaults") { engine.resetCodecPreferencesToDefaults() }
            }
            .padding(10)
        }
    }

    private func setEnabled(_ enabled: Bool, for id: String) {
        var codecs = engine.codecPreferences
        guard let index = codecs.firstIndex(where: { $0.id == id }) else { return }
        codecs[index].enabled = enabled
        engine.setCodecPreferences(codecs)
    }

    private func loadOnce() {
        guard !loaded else { return }
        loaded = true
        let account = engine.account
        domain = account.domain
        username = account.username
        transport = account.transport
        outsidePrefix = account.dialPlan.outsideLinePrefix
        internationalPrefix = account.dialPlan.internationalPrefix ?? ""
        natRewrite = account.natRewrite
        stunServer = account.stunServer ?? ""
        iceEnabled = account.iceEnabled
        if account.isConfigured {
            password = KeychainStore.password(for: account.keychainKey) ?? ""
        }
    }

    private func apply() {
        let plan = DialPlan(
            outsideLinePrefix: outsidePrefix,
            internationalPrefix: internationalPrefix.isEmpty ? nil : internationalPrefix)
        let stun = stunServer.trimmingCharacters(in: .whitespaces)
        let config = AccountConfig(
            domain: domain.trimmingCharacters(in: .whitespaces),
            username: username.trimmingCharacters(in: .whitespaces),
            transport: transport,
            dialPlan: plan,
            natRewrite: natRewrite,
            stunServer: stun.isEmpty ? nil : stun,
            iceEnabled: iceEnabled && !stun.isEmpty)
        engine.applyAccount(config, password: password)
    }
}
