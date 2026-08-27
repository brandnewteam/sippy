// M0 spike: throwaway CLI to validate the linphone SDK before building the app.
//
//   sippy-spike codecs
//       List the audio codecs present in the prebuilt SDK (verifies G.729).
//   sippy-spike register
//       Register against a PBX. Reads SIPPY_DOMAIN, SIPPY_USER, SIPPY_PASSWORD
//       (optional SIPPY_TRANSPORT=udp|tcp|tls, default udp).
//   sippy-spike call <number-or-sip-uri>
//       Register, then place a call. Ctrl-C to hang up.

import Foundation
import linphonesw
import SippyCore

// KEY=VALUE pairs from ./.env (the committed .env.example documents the keys);
// real environment variables win over the file.
let dotEnv: [String: String] = {
    guard let contents = try? String(contentsOfFile: ".env", encoding: .utf8) else { return [:] }
    var values: [String: String] = [:]
    for line in contents.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { continue }
        values[String(trimmed[..<eq])] = String(trimmed[trimmed.index(after: eq)...])
    }
    return values
}()

func env(_ name: String) -> String? {
    ProcessInfo.processInfo.environment[name] ?? dotEnv[name]
}

func requireEnv(_ name: String) -> String {
    guard let value = env(name), !value.isEmpty else {
        fputs("error: \(name) not set\n", stderr)
        exit(2)
    }
    return value
}

func makeCore() throws -> Core {
    // Our self-built mediastreamer2 plugins (libmsbcg729 for G.729) live in
    // Vendor/lib; the SDK's prebuilt binaries don't include G.729.
    let pluginsDir = env("SIPPY_PLUGINS_DIR")
        ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Vendor/lib").path
    Factory.Instance.mspluginsDir = pluginsDir
    let core = try Factory.Instance.createCore(configPath: nil, factoryConfigPath: nil, systemContext: nil)
    core.videoActivationPolicy?.automaticallyAccept = false
    core.videoActivationPolicy?.automaticallyInitiate = false
    return core
}

func listCodecs(_ core: Core) {
    print("Audio codecs in SDK \(Core.getVersion):")
    for pt in core.audioPayloadTypes {
        let state = pt.enabled() ? "enabled " : "disabled"
        print("  [\(state)] \(pt.mimeType)/\(pt.clockRate)/\(pt.channels)  \(pt.description)")
    }
    let hasG729 = core.audioPayloadTypes.contains { $0.mimeType.uppercased() == "G729" }
    print(hasG729 ? "\n✅ G.729 is present" : "\n❌ G.729 is NOT in this SDK build")
}

func setUpAccount(_ core: Core) throws {
    let domain = requireEnv("SIPPY_DOMAIN")
    let user = requireEnv("SIPPY_USER")
    let password = requireEnv("SIPPY_PASSWORD")
    let transport = (env("SIPPY_TRANSPORT") ?? "udp").lowercased()

    let auth = try Factory.Instance.createAuthInfo(
        username: user, userid: nil, passwd: password, ha1: nil, realm: nil, domain: domain)
    core.addAuthInfo(info: auth)

    let params = try core.createAccountParams()
    try params.setIdentityaddress(newValue: Factory.Instance.createAddress(addr: "sip:\(user)@\(domain)"))
    try params.setServeraddr(newValue: "sip:\(domain);transport=\(transport)")
    params.registerEnabled = true

    let account = try core.createAccount(params: params)
    try core.addAccount(account: account)
    core.defaultAccount = account
}

// Keeps the core iterating on the main run loop; linphone requires periodic
// iterate() calls from a single thread.
func runLoop(_ core: Core) -> Never {
    let timer = Timer(timeInterval: 0.02, repeats: true) { _ in core.iterate() }
    RunLoop.main.add(timer, forMode: .common)
    RunLoop.main.run()
    exit(0)
}

let arguments = CommandLine.arguments.dropFirst()
guard let command = arguments.first else {
    fputs("usage: sippy-spike codecs | register | call <number-or-sip-uri>\n", stderr)
    exit(2)
}

LoggingService.Instance.logLevel = env("SIPPY_DEBUG") != nil ? .Debug : .Warning

let core = try makeCore()

// SIPPY_CODECS=G729 (comma-separated mime types) restricts the offered audio
// codecs — used to force-test negotiation of a specific codec.
if let filter = env("SIPPY_CODECS") {
    let wanted = filter.split(separator: ",").map {
        $0.trimmingCharacters(in: .whitespaces).lowercased()
    }
    for pt in core.audioPayloadTypes {
        _ = pt.enable(enabled: wanted.contains(pt.mimeType.lowercased()))
    }
    let enabled = core.audioPayloadTypes.filter { $0.enabled() }
        .map { "\($0.mimeType)/\($0.clockRate)" }
        .joined(separator: ", ")
    print("codec filter active: \(enabled)")
}

switch command {
case "codecs":
    listCodecs(core)

case "register":
    try setUpAccount(core)
    let delegate = CoreDelegateStub(onAccountRegistrationStateChanged: { _, _, state, message in
        print("registration: \(state) — \(message)")
        if state == .Ok { exit(0) }
        if state == .Failed { exit(1) }
    })
    core.addDelegate(delegate: delegate)
    try core.start()
    runLoop(core)

case "receive":
    // Registers and waits for an incoming call, logging every state change.
    // SIPPY_AUTOANSWER=<seconds> answers after that delay; otherwise it just
    // keeps ringing until the caller gives up.
    try setUpAccount(core)
    let autoAnswer = env("SIPPY_AUTOANSWER").flatMap(Double.init)
    let delegate = CoreDelegateStub(
        onCallStateChanged: { _, call, state, message in
            print("call: \(state) — \(message)")
            if state == .IncomingReceived, let autoAnswer {
                DispatchQueue.main.asyncAfter(deadline: .now() + autoAnswer) {
                    print("auto-answering…")
                    try? call.accept()
                }
            }
            if state == .StreamsRunning, let payload = call.currentParams?.usedAudioPayloadType {
                print("negotiated codec: \(payload.mimeType)/\(payload.clockRate)")
            }
        },
        onAccountRegistrationStateChanged: { _, _, state, message in
            print("registration: \(state) — \(message)")
            if state == .Ok { print("waiting for incoming calls…") }
            if state == .Failed { exit(1) }
        })
    core.addDelegate(delegate: delegate)
    try core.start()
    runLoop(core)

case "call":
    guard let target = arguments.dropFirst().first else {
        fputs("usage: sippy-spike call <number-or-sip-uri>\n", stderr)
        exit(2)
    }
    try setUpAccount(core)
    let domain = requireEnv("SIPPY_DOMAIN")
    // The spike dials verbatim except for normalization; prefix rules are
    // exercised properly in SippyCore's unit tests.
    let uri = target.hasPrefix("sip:")
        ? target
        : "sip:\(DialPlan().apply(to: target, origin: .dialpad))@\(domain)"

    let delegate = CoreDelegateStub(
        onCallStateChanged: { _, call, state, message in
            print("call: \(state) — \(message)")
            switch state {
            case .StreamsRunning:
                if let payload = call.currentParams?.usedAudioPayloadType {
                    print("negotiated codec: \(payload.mimeType)/\(payload.clockRate)")
                }
            case .End, .Error, .Released:
                exit(state == .Error ? 1 : 0)
            default:
                break
            }
        },
        onAccountRegistrationStateChanged: { core, _, state, message in
            print("registration: \(state) — \(message)")
            if state == .Ok {
                print("calling \(uri) …")
                if core.invite(url: uri) == nil {
                    fputs("error: could not create call\n", stderr)
                    exit(1)
                }
            }
            if state == .Failed { exit(1) }
        })
    core.addDelegate(delegate: delegate)
    signal(SIGINT, SIG_IGN)
    let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigint.setEventHandler {
        print("\nhanging up…")
        try? core.terminateAllCalls()
        exit(0)
    }
    sigint.resume()
    try core.start()
    runLoop(core)

default:
    fputs("unknown command: \(command)\n", stderr)
    exit(2)
}
