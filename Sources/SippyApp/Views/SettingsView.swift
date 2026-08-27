import SwiftUI
import SippyCore

struct SettingsView: View {
    @Environment(SIPEngine.self) private var engine

    @State private var domain = ""
    @State private var username = ""
    @State private var password = ""
    @State private var transport: AccountConfig.Transport = .udp
    @State private var outsidePrefix = ""
    @State private var internationalPrefix = ""
    @State private var loaded = false

    var body: some View {
        TabView {
            accountTab
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            audioTab
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }
        }
        .frame(width: 420)
        .onAppear(perform: loadOnce)
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

    private func loadOnce() {
        guard !loaded else { return }
        loaded = true
        let account = engine.account
        domain = account.domain
        username = account.username
        transport = account.transport
        outsidePrefix = account.dialPlan.outsideLinePrefix
        internationalPrefix = account.dialPlan.internationalPrefix ?? ""
        if account.isConfigured {
            password = KeychainStore.password(for: account.keychainKey) ?? ""
        }
    }

    private func apply() {
        let plan = DialPlan(
            outsideLinePrefix: outsidePrefix,
            internationalPrefix: internationalPrefix.isEmpty ? nil : internationalPrefix)
        let config = AccountConfig(
            domain: domain.trimmingCharacters(in: .whitespaces),
            username: username.trimmingCharacters(in: .whitespaces),
            transport: transport,
            dialPlan: plan)
        engine.applyAccount(config, password: password)
    }
}
