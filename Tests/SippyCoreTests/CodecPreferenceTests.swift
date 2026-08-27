import Testing
@testable import SippyCore

@Suite struct CodecPreferenceTests {
    private func codec(_ mime: String, _ rate: Int, channels: Int = 1) -> CodecPreference {
        CodecPreference(mime: mime, clockRate: rate, channels: channels, enabled: false)
    }

    // A realistic linphone codec lineup, deliberately shuffled.
    private var available: [CodecPreference] {
        [
            codec("speex", 16000), codec("PCMU", 8000), codec("G729", 8000),
            codec("opus", 48000, channels: 2), codec("GSM", 8000),
            codec("PCMA", 8000), codec("G722", 8000),
        ]
    }

    @Test func defaultListOrder() {
        let list = CodecDefaults.defaultList(available: available)
        let enabled = list.filter(\.enabled).map { $0.mime.lowercased() }
        #expect(enabled == ["opus", "g722", "pcmu", "pcma", "g729"])
    }

    @Test func defaultListDisablesTheRest() {
        let list = CodecDefaults.defaultList(available: available)
        let disabled = list.filter { !$0.enabled }.map { $0.mime.lowercased() }
        #expect(disabled.contains("speex"))
        #expect(disabled.contains("gsm"))
        // Disabled codecs come after all enabled ones.
        let firstDisabled = list.firstIndex { !$0.enabled }!
        #expect(list[firstDisabled...].allSatisfy { !$0.enabled })
    }

    @Test func mergeEmptyStoredFallsBackToDefaults() {
        let merged = CodecDefaults.merge(stored: [], available: available)
        #expect(merged == CodecDefaults.defaultList(available: available))
    }

    @Test func mergeKeepsStoredOrderAndFlags() {
        // User made G.729 top priority and turned Opus off.
        var stored = CodecDefaults.defaultList(available: available)
        let g729 = stored.remove(at: stored.firstIndex { $0.mime == "G729" }!)
        stored.insert(g729, at: 0)
        stored[stored.firstIndex { $0.mime == "opus" }!].enabled = false

        let merged = CodecDefaults.merge(stored: stored, available: available)
        #expect(merged.first?.mime == "G729")
        #expect(merged.first { $0.mime == "opus" }?.enabled == false)
    }

    @Test func mergeDropsVanishedAndAppendsNew() {
        let stored = CodecDefaults.defaultList(available: available)
        // New SDK build: speex gone, iLBC appeared.
        var newAvailable = available.filter { $0.mime != "speex" }
        newAvailable.append(codec("iLBC", 8000))

        let merged = CodecDefaults.merge(stored: stored, available: newAvailable)
        #expect(!merged.contains { $0.mime == "speex" })
        let ilbc = merged.last { $0.mime == "iLBC" }
        #expect(ilbc != nil)
        #expect(ilbc?.enabled == false)  // not default-enabled
        #expect(merged.last?.mime == "iLBC")  // appended, ordering untouched
    }

    @Test func opusStereoAndMonoAreDistinct() {
        let stereo = codec("opus", 48000, channels: 2)
        let mono = codec("opus", 48000, channels: 1)
        #expect(stereo.id != mono.id)
    }
}
