import Foundation
import Observation
import SippyCore
import linphonesw

/// The one object that talks to liblinphone. Runs on the main actor: the
/// linphone Core is iterated from a main-thread timer, so every delegate
/// callback also arrives on the main thread and can mutate observable state
/// directly. Views never import linphonesw — they see only the value types
/// below.
@MainActor
@Observable
public final class SIPEngine {
    public enum RegistrationStatus: Equatable {
        case unconfigured
        case connecting
        case registered
        case failed(String)
    }

    public enum CallPhase: Equatable {
        case ringingIncoming
        case ringingOutgoing
        case active
        case held
        case heldByRemote
        case ending
    }

    public enum CallDirection: Equatable { case incoming, outgoing }

    public struct CallInfo: Equatable {
        public var direction: CallDirection
        public var remoteDisplay: String
        public var remoteNumber: String
        public var remoteURI: String
        public var phase: CallPhase
        public var isMuted: Bool
        public var codec: String?
        public var startedAt: Date?
    }

    /// Summary handed to `onCallFinished` when a call is fully released —
    /// the app layer turns these into history records.
    public struct FinishedCall {
        public var direction: CallDirection
        public var remoteNumber: String
        public var remoteDisplay: String
        public var ringStartedAt: Date
        public var connectedAt: Date?
        public var endedAt: Date
        public var wasDeclinedLocally: Bool
        public var errorMessage: String?
        public var codec: String?
    }

    public struct AudioDeviceInfo: Equatable, Identifiable {
        public let id: String
        public let name: String
        public let isInput: Bool
    }

    public private(set) var registration: RegistrationStatus = .unconfigured
    public private(set) var call: CallInfo?
    public private(set) var lastCallError: String?
    public private(set) var inputDevices: [AudioDeviceInfo] = []
    public private(set) var outputDevices: [AudioDeviceInfo] = []
    public private(set) var selectedInputID: String?
    public private(set) var selectedOutputID: String?

    public var account: AccountConfig

    /// Resolves a number to a display name (Sippy contacts, then system
    /// contacts). Set by the app layer.
    public var displayNameResolver: ((String) -> String?)?
    /// Invoked once per call after it is fully released.
    public var onCallFinished: ((FinishedCall) -> Void)?

    private var core: Core?
    private var delegate: CoreDelegateStub?
    private var iterateTimer: Timer?
    private var activeCall: Call?
    private var ringStartedAt: Date?
    private var declinedLocally = false

    public init() {
        account = AccountConfigStore.load() ?? AccountConfig()
    }

    // MARK: - Lifecycle

    public func start() {
        guard core == nil else { return }
        do {
            LoggingService.Instance.logLevel = ProcessInfo.processInfo.environment["SIPPY_DEBUG"] != nil ? .Debug : .Warning
            Factory.Instance.mspluginsDir = Self.pluginsDirectory()
            let core = try Factory.Instance.createCore(configPath: nil, factoryConfigPath: nil, systemContext: nil)
            core.videoActivationPolicy?.automaticallyAccept = false
            core.videoActivationPolicy?.automaticallyInitiate = false
            installDelegate(on: core)
            try core.start()
            self.core = core

            let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.core?.iterate() }
            }
            RunLoop.main.add(timer, forMode: .common)
            iterateTimer = timer

            refreshAudioDevices()
            if account.isConfigured {
                applyAccount(account, password: KeychainStore.password(for: account.keychainKey) ?? "")
            }
        } catch {
            registration = .failed("Could not start SIP engine: \(error)")
        }
    }

    // MARK: - Account

    public func applyAccount(_ config: AccountConfig, password: String) {
        guard let core else { return }
        account = config
        AccountConfigStore.save(config)
        KeychainStore.setPassword(password, for: config.keychainKey)

        core.clearAccounts()
        core.clearAllAuthInfo()
        guard config.isConfigured else {
            registration = .unconfigured
            return
        }
        do {
            let auth = try Factory.Instance.createAuthInfo(
                username: config.username, userid: nil, passwd: password,
                ha1: nil, realm: nil, domain: config.domain)
            core.addAuthInfo(info: auth)

            let params = try core.createAccountParams()
            try params.setIdentityaddress(
                newValue: Factory.Instance.createAddress(addr: "sip:\(config.username)@\(config.domain)"))
            try params.setServeraddr(
                newValue: "sip:\(config.domain);transport=\(config.transport.rawValue)")
            params.registerEnabled = true
            let sipAccount = try core.createAccount(params: params)
            try core.addAccount(account: sipAccount)
            core.defaultAccount = sipAccount
            registration = .connecting
        } catch {
            registration = .failed("Invalid account settings: \(error)")
        }
    }

    // MARK: - Calls

    public func dial(_ raw: String, origin: NumberOrigin) {
        guard let core, call == nil, account.isConfigured else { return }
        let number = account.dialPlan.apply(to: raw, origin: origin)
        guard !number.isEmpty else { return }
        lastCallError = nil
        let uri = number.hasPrefix("sip:") ? number : "sip:\(number)@\(account.domain)"
        if core.invite(url: uri) == nil {
            lastCallError = "Could not start the call."
        }
    }

    /// Entry point for URLs, the Services menu, and paste-and-dial.
    public func handle(_ request: DialRequest) {
        switch request {
        case .number(let number):
            dial(number, origin: .external)
        case .uri(let uri):
            dialURI(uri)
        }
    }

    /// Dials a complete SIP URI verbatim (no dial-plan rewriting).
    public func dialURI(_ uri: String) {
        guard let core, call == nil else { return }
        lastCallError = nil
        if core.invite(url: uri) == nil {
            lastCallError = "Could not start the call."
        }
    }

    public func answer() {
        try? activeCall?.accept()
    }

    public func decline() {
        declinedLocally = true
        try? activeCall?.decline(reason: .Declined)
    }

    public func hangUp() {
        try? activeCall?.terminate()
    }

    public func toggleMute() {
        guard let core else { return }
        core.micEnabled.toggle()
        call?.isMuted = !core.micEnabled
    }

    public func toggleHold() {
        guard let activeCall else { return }
        if call?.phase == .held {
            try? activeCall.resume()
        } else {
            try? activeCall.pause()
        }
    }

    public func sendDTMF(_ digit: Character) {
        guard let ascii = digit.asciiValue else { return }
        try? activeCall?.sendDtmf(dtmf: CChar(ascii))
    }

    // MARK: - Audio devices

    public func refreshAudioDevices() {
        guard let core else { return }
        let devices = core.audioDevices
        inputDevices = devices
            .filter { $0.hasCapability(capability: .CapabilityRecord) }
            .map { AudioDeviceInfo(id: $0.id, name: $0.deviceName, isInput: true) }
        outputDevices = devices
            .filter { $0.hasCapability(capability: .CapabilityPlay) }
            .map { AudioDeviceInfo(id: $0.id, name: $0.deviceName, isInput: false) }
        selectedInputID = core.inputAudioDevice?.id ?? core.defaultInputAudioDevice?.id
        selectedOutputID = core.outputAudioDevice?.id ?? core.defaultOutputAudioDevice?.id
    }

    public func selectInputDevice(id: String) {
        guard let core, let device = core.audioDevices.first(where: { $0.id == id }) else { return }
        core.inputAudioDevice = device
        activeCall?.inputAudioDevice = device
        selectedInputID = id
    }

    public func selectOutputDevice(id: String) {
        guard let core, let device = core.audioDevices.first(where: { $0.id == id }) else { return }
        core.outputAudioDevice = device
        activeCall?.outputAudioDevice = device
        selectedOutputID = id
    }

    // MARK: - Internals

    private func installDelegate(on core: Core) {
        let delegate = CoreDelegateStub(
            onCallStateChanged: { [weak self] _, lpCall, state, message in
                MainActor.assumeIsolated { self?.callChanged(lpCall, state: state, message: message) }
            },
            onAudioDevicesListUpdated: { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshAudioDevices() }
            },
            onAccountRegistrationStateChanged: { [weak self] _, _, state, message in
                MainActor.assumeIsolated { self?.registrationChanged(state, message: message) }
            })
        core.addDelegate(delegate: delegate)
        self.delegate = delegate
    }

    private func registrationChanged(_ state: RegistrationState, message: String) {
        switch state {
        case .Ok:
            registration = .registered
        case .Progress, .Refreshing:
            registration = .connecting
        case .Failed:
            registration = .failed(message)
        case .None, .Cleared:
            registration = account.isConfigured ? .connecting : .unconfigured
        }
    }

    private func callChanged(_ lpCall: Call, state: Call.State, message: String) {
        // Single-call policy for M1: a second incoming call is politely refused.
        if activeCall != nil, lpCall !== activeCall, state == .IncomingReceived {
            try? lpCall.decline(reason: .Busy)
            return
        }

        switch state {
        case .IncomingReceived, .PushIncomingReceived:
            activeCall = lpCall
            ringStartedAt = Date()
            declinedLocally = false
            call = makeInfo(for: lpCall, phase: .ringingIncoming)
        case .OutgoingInit, .OutgoingProgress, .OutgoingRinging, .OutgoingEarlyMedia:
            activeCall = lpCall
            if call == nil { ringStartedAt = Date(); declinedLocally = false }
            call = makeInfo(for: lpCall, phase: .ringingOutgoing)
        case .Connected:
            call = makeInfo(for: lpCall, phase: .active, startedAt: call?.startedAt ?? Date())
        case .StreamsRunning, .Updating, .UpdatedByRemote, .EarlyUpdating, .EarlyUpdatedByRemote:
            call = makeInfo(for: lpCall, phase: .active, startedAt: call?.startedAt ?? Date())
        case .Pausing, .Paused:
            call?.phase = .held
        case .Resuming:
            call?.phase = .active
        case .PausedByRemote:
            call?.phase = .heldByRemote
        case .End:
            call?.phase = .ending
        case .Error:
            lastCallError = message
            call?.phase = .ending
        case .Released:
            if let info = call {
                onCallFinished?(FinishedCall(
                    direction: info.direction,
                    remoteNumber: info.remoteNumber,
                    remoteDisplay: info.remoteDisplay,
                    ringStartedAt: ringStartedAt ?? Date(),
                    connectedAt: info.startedAt,
                    endedAt: Date(),
                    wasDeclinedLocally: declinedLocally,
                    errorMessage: lastCallError,
                    codec: info.codec))
            }
            activeCall = nil
            call = nil
            ringStartedAt = nil
        case .Idle, .IncomingEarlyMedia, .Referred:
            break
        }
    }

    private func makeInfo(for lpCall: Call, phase: CallPhase, startedAt: Date? = nil) -> CallInfo {
        let address = lpCall.remoteAddress
        let number = address?.username ?? ""
        let display = displayNameResolver?(number)
            ?? address?.displayName
            ?? (number.isEmpty ? "Unknown" : number)
        var codec: String?
        if let payload = lpCall.currentParams?.usedAudioPayloadType {
            codec = "\(payload.mimeType)/\(payload.clockRate)"
        }
        return CallInfo(
            direction: lpCall.dir == .Incoming ? .incoming : .outgoing,
            remoteDisplay: display,
            remoteNumber: number,
            remoteURI: lpCall.remoteAddressAsString ?? "",
            phase: phase,
            isMuted: !(core?.micEnabled ?? true),
            codec: codec,
            startedAt: startedAt)
    }

    /// Bundled app: mediastreamer plugins ship in Contents/Frameworks.
    /// Bare executable (swift run): fall back to Vendor/lib in the repo.
    private static func pluginsDirectory() -> String {
        if let frameworks = Bundle.main.privateFrameworksPath,
           FileManager.default.fileExists(atPath: frameworks + "/libmsbcg729.so") {
            return frameworks
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Vendor/lib").path
    }
}
