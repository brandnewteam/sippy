import Testing
@testable import SippyCore

@Suite struct AudioDeviceNamesTests {
    @Test func dropsUIDSuffix() {
        #expect(AudioDeviceNames.displayNames(for: [
            "MacBook Pro Speakers (BuiltInSpeakerDevice)",
            "M28U (1C540028-0000-0000-1021-0104C53F2478)",
            "USB SPDIF OUT (AppleUSBAudioEngine:C-Media Electronics Inc.:USB SPDIF OUT:123100:1)",
        ]) == ["MacBook Pro Speakers", "M28U", "USB SPDIF OUT"])
    }

    @Test func namesTheSystemDefault() {
        #expect(AudioDeviceNames.displayNames(for: ["Default Playback", "MacBook Pro Speakers (B)"])
            == ["System Default", "MacBook Pro Speakers"])
        #expect(AudioDeviceNames.displayNames(for: ["Default Capture"]) == ["System Default"])
    }

    @Test func keepsNamesWithoutSuffix() {
        #expect(AudioDeviceNames.displayNames(for: ["Headset", "(Weird)"]) == ["Headset", "(Weird)"])
    }

    @Test func keepsUIDWhenShortNamesCollide() {
        let names = ["USB Audio (A1)", "USB Audio (B2)", "Speakers (S)"]
        #expect(AudioDeviceNames.displayNames(for: names)
            == ["USB Audio (A1)", "USB Audio (B2)", "Speakers"])
    }
}
