import Foundation

/// SIP account settings, minus the password (which lives in the Keychain,
/// see `KeychainStore`).
public struct AccountConfig: Codable, Equatable, Sendable {
    public enum Transport: String, Codable, CaseIterable, Sendable {
        case udp, tcp, tls
    }

    public var domain: String
    public var username: String
    public var transport: Transport
    public var dialPlan: DialPlan
    /// Ordered codec priority list; empty means "use the defaults" (it is
    /// reconciled against the SIP stack's codec list at startup).
    public var codecPreferences: [CodecPreference]
    /// Ringtone filename (bundled or imported); nil = Sippy's default.
    public var ringtone: String?
    /// Rewrite Contact/Via with the public address learned from responses
    /// (received/rport) — Telephone's "Update IP Address". On by default;
    /// harmless when the PBX fixes it server-side.
    public var natRewrite: Bool
    /// Optional STUN server (host or host:port) for NAT traversal.
    public var stunServer: String?
    /// Use ICE candidate negotiation (needs a STUN server to be useful).
    public var iceEnabled: Bool
    /// Only attempt registration while a network route to the domain exists
    /// (e.g. one pushed by a VPN). Off by default: for a public registrar the
    /// probe is pure overhead.
    public var requireRoute: Bool

    public init(
        domain: String = "",
        username: String = "",
        transport: Transport = .udp,
        dialPlan: DialPlan = DialPlan(),
        codecPreferences: [CodecPreference] = [],
        ringtone: String? = nil,
        natRewrite: Bool = true,
        stunServer: String? = nil,
        iceEnabled: Bool = false,
        requireRoute: Bool = false
    ) {
        self.domain = domain
        self.username = username
        self.transport = transport
        self.dialPlan = dialPlan
        self.codecPreferences = codecPreferences
        self.ringtone = ringtone
        self.natRewrite = natRewrite
        self.stunServer = stunServer
        self.iceEnabled = iceEnabled
        self.requireRoute = requireRoute
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        domain = try container.decode(String.self, forKey: .domain)
        username = try container.decode(String.self, forKey: .username)
        transport = try container.decode(Transport.self, forKey: .transport)
        dialPlan = try container.decode(DialPlan.self, forKey: .dialPlan)
        // decodeIfPresent everywhere below: absent in configs from earlier
        // milestones.
        codecPreferences =
            try container.decodeIfPresent([CodecPreference].self, forKey: .codecPreferences) ?? []
        ringtone = try container.decodeIfPresent(String.self, forKey: .ringtone)
        natRewrite = try container.decodeIfPresent(Bool.self, forKey: .natRewrite) ?? true
        stunServer = try container.decodeIfPresent(String.self, forKey: .stunServer)
        iceEnabled = try container.decodeIfPresent(Bool.self, forKey: .iceEnabled) ?? false
        requireRoute = try container.decodeIfPresent(Bool.self, forKey: .requireRoute) ?? false
    }

    public var isConfigured: Bool { !domain.isEmpty && !username.isEmpty }

    /// Keychain account key for this SIP identity.
    public var keychainKey: String { "\(username)@\(domain)" }
}

/// Persists the account configuration in UserDefaults (password excluded).
public enum AccountConfigStore {
    private static let key = "sippy.account"

    public static func load(defaults: UserDefaults = .standard) -> AccountConfig? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AccountConfig.self, from: data)
    }

    public static func save(_ config: AccountConfig, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: key)
        }
    }
}
