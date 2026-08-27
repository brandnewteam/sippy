import AppKit
import Foundation
import Network
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
        /// Route gating is on and no route to the domain exists (VPN down):
        /// registration is deliberately not being attempted.
        case waitingForRoute
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

    /// One ~1s sample of the audio stream's health, taken whenever the SIP
    /// stack refreshes its call statistics. Jitter/loss come in two flavors:
    /// what we measure on the stream we receive (download) and what the far
    /// end reports about the stream we send (upload, via RTCP).
    public struct CallStatsSnapshot: Equatable, Sendable {
        public var time: Date
        public var uploadKbps: Float
        public var downloadKbps: Float
        public var downloadJitterMs: Float
        public var uploadJitterMs: Float
        public var rttMs: Float
        public var downloadLossPct: Float
        public var uploadLossPct: Float
        public var iceState: String
        public var encryption: String
    }

    public private(set) var registration: RegistrationStatus = .unconfigured
    public private(set) var call: CallInfo?
    public private(set) var lastCallError: String?
    public private(set) var inputDevices: [AudioDeviceInfo] = []
    public private(set) var outputDevices: [AudioDeviceInfo] = []
    public private(set) var selectedInputID: String?
    public private(set) var selectedOutputID: String?

    /// Effective codec priority list (stored preferences reconciled with what
    /// the stack offers). Order = priority.
    public private(set) var codecPreferences: [CodecPreference] = []
    /// Rolling per-second stats for the current call (cleared when a new call
    /// starts). Last element is the freshest.
    public private(set) var statsHistory: [CallStatsSnapshot] = []
    public var currentStats: CallStatsSnapshot? { statsHistory.last }
    /// Captured SIP messages, newest last. Only fills while `sipTraceEnabled`.
    public private(set) var sipTrace: [SIPTraceEntry] = []
    public private(set) var sipTraceEnabled = UserDefaults.standard.bool(forKey: SIPEngine.sipTraceKey)

    /// Devices the ring can play on (legacy sound-card names — the modern
    /// AudioDevice API in this SDK version has no ring routing yet).
    public private(set) var ringerDevices: [String] = []
    public private(set) var selectedRingerDevice: String?

    private static let sipTraceKey = "sippy.sipTraceEnabled"
    private static let ringerDeviceKey = "sippy.ringerDevice"
    private static let statsHistoryLimit = 600
    private static let sipTraceLimit = 500

    public var account: AccountConfig

    /// Resolves a number to a display name (Sippy contacts, then system
    /// contacts). Set by the app layer.
    public var displayNameResolver: ((String) -> String?)?
    /// Invoked once per call after it is fully released.
    public var onCallFinished: ((FinishedCall) -> Void)?

    private var core: Core?
    private var delegate: CoreDelegateStub?
    private var logDelegate: LoggingServiceDelegateStub?
    private var iterateTimer: Timer?
    private var pathMonitor: NWPathMonitor?
    private var wakeObserver: NSObjectProtocol?
    private var routeProbeGeneration = 0
    private var routeProbeTask: Task<Void, Never>?
    /// True while route gating has told the stack to stand down.
    private var routeGateClosed = false
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
            applyLogLevel()
            installLogCapture()
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
            refreshRingerDevices()
            if let stored = UserDefaults.standard.string(forKey: Self.ringerDeviceKey) {
                setRingerDevice(stored)
            }
            codecPreferences = CodecDefaults.merge(
                stored: account.codecPreferences, available: snapshotAvailableCodecs())
            applyCodecPreferencesToCore()
            if account.isConfigured {
                loadStoredCredentialsAndRegister()
            }
            startHardeningMonitors()
        } catch {
            registration = .failed("Could not start SIP engine: \(error)")
        }
    }

    // MARK: - Account

    /// Reads the stored password off the main thread: the keychain item's
    /// ACL is bound to the code signature, which changes with every ad-hoc
    /// rebuild, so SecItemCopyMatching can block on an authorization dialog —
    /// doing that on the main thread at launch beachballs the whole app.
    private func loadStoredCredentialsAndRegister() {
        let key = account.keychainKey
        registration = .connecting
        Task.detached(priority: .userInitiated) {
            let password = KeychainStore.password(for: key) ?? ""
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.configureCore(with: self.account, password: password)
            }
        }
    }

    public func applyAccount(_ config: AccountConfig, password: String) {
        guard core != nil else { return }
        // Codec preferences and the ringtone are managed by their own
        // settings UIs, not the account form — carry the current values over.
        var config = config
        config.codecPreferences = codecPreferences
        config.ringtone = account.ringtone
        account = config
        AccountConfigStore.save(config)
        // User-initiated (Apply button), so a keychain prompt here is fine.
        KeychainStore.setPassword(password, for: config.keychainKey)
        configureCore(with: config, password: password)
    }

    /// Points the SIP stack at the account — everything after credentials
    /// are in hand. Never touches the keychain.
    private func configureCore(with config: AccountConfig, password: String) {
        guard let core else { return }
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
            try params.setServeraddress(
                newValue: Factory.Instance.createAddress(
                    addr: "sip:\(config.domain);transport=\(config.transport.rawValue)"))
            params.registerEnabled = true

            // NAT traversal (§2.6): the received/rport Contact rewrite is
            // liblinphone's "NAT helper"; STUN/ICE ride a NatPolicy.
            core.config?.setBool(section: "net", key: "enable_nat_helper", value: config.natRewrite)
            let stun = config.stunServer?.trimmingCharacters(in: .whitespaces) ?? ""
            if !stun.isEmpty || config.iceEnabled {
                let nat = try core.createNatPolicy()
                if !stun.isEmpty {
                    nat.stunServer = stun
                    nat.stunEnabled = true
                }
                nat.iceEnabled = config.iceEnabled
                params.natPolicy = nat
            }
            let sipAccount = try core.createAccount(params: params)
            try core.addAccount(account: sipAccount)
            core.defaultAccount = sipAccount
            registration = .connecting
            if config.requireRoute {
                scheduleRouteProbe()
            } else if routeGateClosed {
                // Gating switched off: hand reachability back to the OS path.
                routeGateClosed = false
                core.networkReachable = true
            }
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

    // MARK: - Ringtone & ringer device

    /// Points the stack's ring player at a sound file; nil restores the SDK
    /// default ring.
    public func setRingtonePath(_ path: String?) {
        core?.ring = path
    }

    /// User picked a ringtone: apply it and persist the choice (by filename,
    /// so the library can move) with the account.
    public func setRingtone(fileName: String?, path: String?) {
        core?.ring = path
        account.ringtone = fileName
        AccountConfigStore.save(account)
    }

    public func refreshRingerDevices() {
        guard let core else { return }
        let compat: RingerDeviceCompat = core
        ringerDevices = compat.soundDeviceNames
        selectedRingerDevice = compat.currentRingerDevice
    }

    /// Routes ringing to a specific output (e.g. speakers while calls go to
    /// the headset). Persisted and re-applied across launches and hot-plugs.
    public func setRingerDevice(_ name: String) {
        guard let core else { return }
        let compat: RingerDeviceCompat = core
        guard compat.soundDeviceNames.contains(name) else { return }
        try? compat.setRingerDeviceName(name)
        selectedRingerDevice = compat.currentRingerDevice
        UserDefaults.standard.set(name, forKey: Self.ringerDeviceKey)
    }

    // MARK: - Hardening

    /// Re-registration triggers that don't come from SIP itself: network path
    /// changes (Wi-Fi ↔ Ethernet ↔ VPN) and wake from sleep.
    private func startHardeningMonitors() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let reachable = path.status == .satisfied
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.networkChanged(reachable: reachable) }
            }
        }
        monitor.start(queue: DispatchQueue(label: "sippy.pathmonitor"))
        pathMonitor = monitor

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let core = self.core else { return }
                if self.account.isConfigured { self.registration = .connecting }
                core.refreshRegisters()
            }
        }
    }

    private func networkChanged(reachable: Bool) {
        guard let core else { return }
        if account.requireRoute, account.isConfigured {
            // Route gating decides reachability itself: probe the domain
            // (debounced — VPN connects flap the path several times).
            if reachable {
                scheduleRouteProbe()
            } else {
                // Invalidate any in-flight probe so a stale "routable"
                // result can't reopen the gate.
                routeProbeGeneration += 1
                routeProbeTask?.cancel()
                routeGate(open: false)
            }
            return
        }
        // Telling the stack about reachability flips make it drop and rebuild
        // its transports; a refresh on the way up re-registers promptly
        // instead of waiting out the register timer.
        core.networkReachable = reachable
        if reachable, account.isConfigured {
            registration = .connecting
            core.refreshRegisters()
        }
    }

    // MARK: - Route gating

    /// Debounced probe: path updates arrive in bursts while a VPN is coming
    /// up, so wait for them to settle before evaluating.
    private func scheduleRouteProbe() {
        routeProbeGeneration += 1
        routeProbeTask?.cancel()
        routeProbeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.probeRoute()
        }
    }

    /// Asks the kernel's routing table (RTM_GET, see `RouteCheck`) whether
    /// the domain is deliverable right now. No SIP traffic, no packets at
    /// all. Runs detached: name resolution can block.
    private func probeRoute() {
        guard account.requireRoute, account.isConfigured else { return }
        let host = Self.probeTarget(for: account.domain).host
        let generation = routeProbeGeneration
        Task.detached(priority: .utility) {
            let routable = RouteCheck.routeAvailable(toHost: host)
            await MainActor.run { [weak self] in
                guard let self, self.routeProbeGeneration == generation else { return }
                self.routeGate(open: routable)
            }
        }
    }

    private func routeGate(open: Bool) {
        guard let core else { return }
        if open {
            let wasClosed = routeGateClosed
            routeGateClosed = false
            core.networkReachable = true
            if wasClosed || registration != .registered {
                registration = .connecting
                core.refreshRegisters()
            }
        } else {
            routeGateClosed = true
            core.networkReachable = false
            registration = .waitingForRoute
        }
    }

    /// The registration destination: the domain's host, and its explicit
    /// port if one is given ("pbx.example.com:5080"), else 5060.
    static func probeTarget(for domain: String) -> (host: String, port: UInt16) {
        let parts = domain.split(separator: ":", maxSplits: 1)
        if parts.count == 2, let port = UInt16(parts[1]) {
            return (String(parts[0]), port)
        }
        return (domain, 5060)
    }

    // MARK: - Codecs

    /// Replaces the codec priority list: reorders and enables/disables the
    /// stack's payload types to match, and persists the list with the account.
    public func setCodecPreferences(_ preferences: [CodecPreference]) {
        codecPreferences = preferences
        applyCodecPreferencesToCore()
        account.codecPreferences = preferences
        AccountConfigStore.save(account)
    }

    public func resetCodecPreferencesToDefaults() {
        setCodecPreferences(CodecDefaults.defaultList(available: snapshotAvailableCodecs()))
    }

    private func snapshotAvailableCodecs() -> [CodecPreference] {
        guard let core else { return [] }
        return core.audioPayloadTypes.map {
            CodecPreference(
                mime: $0.mimeType, clockRate: $0.clockRate,
                channels: $0.channels, enabled: $0.enabled())
        }
    }

    private func applyCodecPreferencesToCore() {
        guard let core else { return }
        let payloads = core.audioPayloadTypes
        var byID: [String: PayloadType] = [:]
        for payload in payloads {
            let id = "\(payload.mimeType.lowercased())/\(payload.clockRate)/\(payload.channels)"
            byID[id] = payload
        }
        var ordered: [PayloadType] = []
        for pref in codecPreferences {
            guard let payload = byID.removeValue(forKey: pref.id) else { continue }
            _ = payload.enable(enabled: pref.enabled)
            ordered.append(payload)
        }
        // Anything the preference list doesn't know: keep it, disabled.
        for payload in byID.values {
            _ = payload.enable(enabled: false)
            ordered.append(payload)
        }
        core.audioPayloadTypes = ordered
    }

    // MARK: - SIP trace

    public func setSIPTraceEnabled(_ enabled: Bool) {
        sipTraceEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.sipTraceKey)
        applyLogLevel()
    }

    public func clearSIPTrace() {
        sipTrace = []
    }

    /// Plain-text dump of the captured trace, for export / bug reports.
    public func sipTraceExportText() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var out = "Sippy SIP trace — exported \(formatter.string(from: Date()))\n"
        out += "Account: \(account.username)@\(account.domain) (\(account.transport.rawValue))\n\n"
        for entry in sipTrace {
            let arrow = entry.direction == .sent ? "→ sent" : entry.direction == .received ? "← received" : "· logged"
            out += "===== \(formatter.string(from: entry.date)) \(arrow) =====\n"
            out += entry.raw + "\n\n"
        }
        return out
    }

    /// SIP messages arrive through the stack's log stream (level Message).
    /// The delegate stays installed permanently; `sipTraceEnabled` just
    /// gates the log level and the capture.
    private func installLogCapture() {
        guard logDelegate == nil else { return }
        let delegate = LoggingServiceDelegateStub(onLogMessageWritten: { [weak self] _, _, _, message in
            // Cheap pre-filter before parsing: every SIP start-line contains
            // "SIP/2.0". Log callbacks can fire off the main thread.
            guard message.contains("SIP/2.0") else { return }
            let date = Date()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.sipTraceEnabled,
                          let entry = SIPTraceParser.parse(logMessage: message, date: date)
                    else { return }
                    self.sipTrace.append(entry)
                    if self.sipTrace.count > Self.sipTraceLimit {
                        self.sipTrace.removeFirst(self.sipTrace.count - Self.sipTraceLimit)
                    }
                }
            }
        })
        LoggingService.Instance.addDelegate(delegate: delegate)
        logDelegate = delegate
    }

    private func applyLogLevel() {
        if ProcessInfo.processInfo.environment["SIPPY_DEBUG"] != nil {
            LoggingService.Instance.logLevel = .Debug
        } else {
            LoggingService.Instance.logLevel = sipTraceEnabled ? .Message : .Warning
        }
    }

    // MARK: - Internals

    private func installDelegate(on core: Core) {
        let delegate = CoreDelegateStub(
            onCallStateChanged: { [weak self] _, lpCall, state, message in
                MainActor.assumeIsolated { self?.callChanged(lpCall, state: state, message: message) }
            },
            onCallStatsUpdated: { [weak self] _, lpCall, stats in
                MainActor.assumeIsolated { self?.statsUpdated(lpCall, stats: stats) }
            },
            onAudioDevicesListUpdated: { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.refreshAudioDevices()
                    self.refreshRingerDevices()
                    // Re-pin the preferred ringer if it just got plugged back in.
                    if let preferred = UserDefaults.standard.string(forKey: Self.ringerDeviceKey),
                       self.ringerDevices.contains(preferred),
                       self.selectedRingerDevice != preferred {
                        self.setRingerDevice(preferred)
                    }
                }
            },
            onAccountRegistrationStateChanged: { [weak self] _, _, state, message in
                MainActor.assumeIsolated { self?.registrationChanged(state, message: message) }
            })
        core.addDelegate(delegate: delegate)
        self.delegate = delegate
    }

    private func registrationChanged(_ state: RegistrationState, message: String) {
        // While the route gate is closed, late failures/teardowns from the
        // stack shouldn't repaint the deliberate "waiting" state as an error.
        if routeGateClosed, state != .Ok {
            registration = .waitingForRoute
            return
        }
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

    private func statsUpdated(_ lpCall: Call, stats: CallStats) {
        guard lpCall === activeCall, stats.type == .Audio else { return }
        let encryption: String
        switch lpCall.currentParams?.mediaEncryption {
        case .SRTP: encryption = "SRTP"
        case .ZRTP: encryption = "ZRTP"
        case .DTLS: encryption = "DTLS-SRTP"
        default: encryption = "None"
        }
        let ice: String
        switch stats.iceState {
        case .NotActivated: ice = "Off"
        case .InProgress: ice = "Negotiating"
        case .HostConnection: ice = "Host"
        case .ReflexiveConnection: ice = "Reflexive"
        case .RelayConnection: ice = "Relay"
        case .Failed: ice = "Failed"
        }
        statsHistory.append(CallStatsSnapshot(
            time: Date(),
            uploadKbps: stats.uploadBandwidth,
            downloadKbps: stats.downloadBandwidth,
            downloadJitterMs: stats.senderInterarrivalJitter * 1000,
            uploadJitterMs: stats.receiverInterarrivalJitter * 1000,
            rttMs: stats.roundTripDelay * 1000,
            downloadLossPct: max(0, stats.localLossRate),
            uploadLossPct: max(0, stats.receiverLossRate),
            iceState: ice,
            encryption: encryption))
        if statsHistory.count > Self.statsHistoryLimit {
            statsHistory.removeFirst(statsHistory.count - Self.statsHistoryLimit)
        }
        // The negotiated codec can change mid-call (re-INVITE); keep it fresh.
        if let payload = lpCall.currentParams?.usedAudioPayloadType {
            call?.codec = "\(payload.mimeType)/\(payload.clockRate)"
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
            statsHistory = []
            call = makeInfo(for: lpCall, phase: .ringingIncoming)
        case .OutgoingInit, .OutgoingProgress, .OutgoingRinging, .OutgoingEarlyMedia:
            activeCall = lpCall
            if call == nil { ringStartedAt = Date(); declinedLocally = false; statsHistory = [] }
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
            remoteURI: lpCall.remoteAddress?.asString() ?? "",
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

/// This SDK version only exposes ring routing through the legacy sound-card
/// API (the modern AudioDevice API has no setUseForRinging yet). Going through
/// a protocol witness keeps the deliberate use of the deprecated members from
/// warning on every build.
private protocol RingerDeviceCompat {
    var soundDeviceNames: [String] { get }
    var currentRingerDevice: String? { get }
    func setRingerDeviceName(_ name: String) throws
}

extension Core: RingerDeviceCompat {
    @available(*, deprecated)
    var soundDeviceNames: [String] { soundDevicesList }
    @available(*, deprecated)
    var currentRingerDevice: String? { ringerDevice }
    @available(*, deprecated)
    func setRingerDeviceName(_ name: String) throws {
        try setRingerdevice(newValue: name)
    }
}
