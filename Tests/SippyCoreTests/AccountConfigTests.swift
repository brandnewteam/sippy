import Foundation
import Testing
@testable import SippyCore

@Suite struct AccountConfigTests {
    /// A config saved by an M1-era build must still decode, with the fields
    /// added in later milestones taking their defaults.
    @Test func decodesLegacyConfig() throws {
        let legacy = """
            {"domain":"pbx.example.com","username":"6001","transport":"udp",
             "dialPlan":{"outsideLinePrefix":"0"}}
            """
        let config = try JSONDecoder().decode(AccountConfig.self, from: Data(legacy.utf8))
        #expect(config.domain == "pbx.example.com")
        #expect(config.codecPreferences.isEmpty)
        #expect(config.ringtone == nil)
        #expect(config.natRewrite == true)
        #expect(config.stunServer == nil)
        #expect(config.iceEnabled == false)
        #expect(config.requireRoute == false)
    }

    @Test func roundTripsAllFields() throws {
        var config = AccountConfig(domain: "pbx", username: "6001")
        config.codecPreferences = [CodecPreference(mime: "G729", clockRate: 8000, enabled: true)]
        config.ringtone = "Marimba.wav"
        config.natRewrite = false
        config.stunServer = "stun.example.com"
        config.iceEnabled = true
        config.requireRoute = true

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AccountConfig.self, from: data)
        #expect(decoded == config)
    }
}
