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

    public init(
        domain: String = "",
        username: String = "",
        transport: Transport = .udp,
        dialPlan: DialPlan = DialPlan()
    ) {
        self.domain = domain
        self.username = username
        self.transport = transport
        self.dialPlan = dialPlan
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
