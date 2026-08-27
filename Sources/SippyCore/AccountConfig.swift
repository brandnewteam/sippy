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

    public init(
        domain: String = "",
        username: String = "",
        transport: Transport = .udp,
        dialPlan: DialPlan = DialPlan(),
        codecPreferences: [CodecPreference] = []
    ) {
        self.domain = domain
        self.username = username
        self.transport = transport
        self.dialPlan = dialPlan
        self.codecPreferences = codecPreferences
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        domain = try container.decode(String.self, forKey: .domain)
        username = try container.decode(String.self, forKey: .username)
        transport = try container.decode(Transport.self, forKey: .transport)
        dialPlan = try container.decode(DialPlan.self, forKey: .dialPlan)
        // Absent in configs saved before M4.
        codecPreferences =
            try container.decodeIfPresent([CodecPreference].self, forKey: .codecPreferences) ?? []
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
