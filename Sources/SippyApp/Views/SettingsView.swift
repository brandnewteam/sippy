import ServiceManagement
import SwiftUI
import SippyCore

struct SettingsView: View {
    @Environment(SIPEngine.self) private var engine
    @Environment(RingtoneLibrary.self) private var ringtones

    @ViewState private var domain = ""
    @ViewState private var username = ""
    @ViewState private var password = ""
    @ViewState private var transport: AccountConfig.Transport = .udp
    @ViewState private var outsidePrefix = ""
    @ViewState private var internationalPrefix = ""
    @ViewState private var natRewrite = true
    @ViewState private var stunServer = ""
    @ViewState private var iceEnabled = false
    @ViewState private var requireRoute = false
    @ViewState private var loaded = false

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            accountTab
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            audioTab
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }
            codecsTab
                .tabItem { Label("Codecs", systemImage: "waveform") }
            RingtoneSettingsTab()
                .tabItem { Label("Ringtones", systemImage: "bell") }
        }
        .onAppear(perform: loadOnce)
        .onDisappear { ringtones.stopPreview() }
    }

    private var accountTab: some View {
        SettingsPane(height: 540) {
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
            Section {
                TextField("Outside line prefix", text: $outsidePrefix, prompt: Text("e.g. 0 or 0*4"))
                TextField("Replace leading + with", text: $internationalPrefix, prompt: Text("e.g. 00 (empty keeps +)"))
            } header: {
                Text("Dialing")
            } footer: {
                SettingsFootnote("The prefix applies to numbers from links and system contacts. The dialpad and Sippy contacts dial verbatim.")
            }
            Section {
                Toggle("Update IP address from server replies", isOn: $natRewrite)
                TextField("STUN server", text: $stunServer, prompt: Text("stun.example.com (optional)"))
                Toggle("Use ICE", isOn: $iceEnabled)
                    .disabled(stunServer.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("NAT Traversal")
            } footer: {
                SettingsFootnote("Leave as-is when the PBX rewrites addresses server-side (Kalliope can).")
            }
            Section {
                Toggle("Register only while a route to the server exists", isOn: $requireRoute)
            } header: {
                Text("Connection")
            } footer: {
                SettingsFootnote("For servers reached over a VPN: don't attempt to connect while the VPN is down, and reconnect as soon as it comes up.")
            }
        } bar: {
            RegistrationStatusLabel()
            Spacer(minLength: 0)
            Button("Apply") { apply() }
                .keyboardShortcut(.defaultAction)
        }
    }

    private var audioTab: some View {
        @Bindable var engine = engine
        return SettingsPane {
            Section {
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
            } footer: {
                SettingsFootnote("Used for calls. The device that rings is set in Ringtones.")
            }
        }
        .onAppear { engine.refreshAudioDevices() }
    }

    /// Order = priority; changes apply immediately (they only take effect on
    /// the next call anyway).
    private var codecsTab: some View {
        // A List, not a form section: grouped forms don't support onMove.
        SettingsPane(height: 480, form: false) {
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
                    .padding(.vertical, 2)
                    .opacity(pref.enabled ? 1 : 0.5)
                }
                .onMove { from, to in
                    var codecs = engine.codecPreferences
                    codecs.move(fromOffsets: from, toOffset: to)
                    engine.setCodecPreferences(codecs)
                }
            }
            .listStyle(.bordered)
        } bar: {
            SettingsBarNote("Drag to set priority. The first enabled codec is offered first.")
            Button("Reset to Defaults") { engine.resetCodecPreferencesToDefaults() }
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
        requireRoute = account.requireRoute
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
            iceEnabled: iceEnabled && !stun.isEmpty,
            requireRoute: requireRoute)
        engine.applyAccount(config, password: password)
    }
}
