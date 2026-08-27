import Foundation

/// One audio codec in the user's preference list. Order in the list is
/// priority (first = most preferred); `enabled` controls whether it is
/// offered at all. Identified by mime/clockRate/channels, the same triple
/// mediastreamer2 uses to tell payload types apart.
public struct CodecPreference: Codable, Equatable, Sendable, Identifiable {
    public var mime: String
    public var clockRate: Int
    public var channels: Int
    public var enabled: Bool

    public init(mime: String, clockRate: Int, channels: Int = 1, enabled: Bool) {
        self.mime = mime
        self.clockRate = clockRate
        self.channels = channels
        self.enabled = enabled
    }

    public var id: String { "\(mime.lowercased())/\(clockRate)/\(channels)" }

    /// Human-facing name, e.g. "Opus 48 kHz stereo", "G.711 A-law".
    public var displayName: String {
        switch mime.lowercased() {
        case "opus": return "Opus"
        case "pcmu": return "G.711 µ-law (PCMU)"
        case "pcma": return "G.711 A-law (PCMA)"
        case "g722": return "G.722"
        case "g729": return "G.729"
        case "speex": return channels > 1 ? "Speex" : "Speex \(clockRate / 1000) kHz"
        case "gsm": return "GSM"
        case "ilbc": return "iLBC"
        case "l16": return "L16 (uncompressed)"
        case "bv16": return "BroadVoice16"
        default: return mime
        }
    }

    public var detail: String {
        let rate = "\(clockRate / 1000) kHz"
        return channels > 1 ? "\(rate), \(channels) ch" : rate
    }
}

/// Sippy's default codec policy: Opus → G.722 → G.711 → G.729 enabled,
/// everything else off. Pure functions so the ordering rules are unit-tested
/// without a SIP stack.
public enum CodecDefaults {
    /// Rank in the default priority order; nil = disabled by default.
    public static func defaultRank(mime: String, clockRate: Int = 0) -> Int? {
        switch mime.lowercased() {
        case "opus": return 0
        case "g722": return 1
        case "pcmu": return 2
        case "pcma": return 3
        case "g729": return 4
        default: return nil
        }
    }

    /// Builds the default preference list from the codecs a SIP stack
    /// actually offers. Default-enabled codecs first in rank order, the rest
    /// appended disabled in their original order.
    public static func defaultList(available: [CodecPreference]) -> [CodecPreference] {
        var ranked: [(rank: Int, pref: CodecPreference)] = []
        var rest: [CodecPreference] = []
        for codec in available {
            if let rank = defaultRank(mime: codec.mime, clockRate: codec.clockRate) {
                var pref = codec
                pref.enabled = true
                ranked.append((rank, pref))
            } else {
                var pref = codec
                pref.enabled = false
                rest.append(pref)
            }
        }
        return ranked.sorted { $0.rank < $1.rank }.map(\.pref) + rest
    }

    /// Reconciles a stored preference list with what the stack offers now:
    /// keeps the stored order and enabled flags for codecs that still exist,
    /// drops vanished ones, appends new codecs (enabled only if
    /// default-enabled, at the end so the user's ordering is untouched).
    public static func merge(
        stored: [CodecPreference],
        available: [CodecPreference]
    ) -> [CodecPreference] {
        guard !stored.isEmpty else { return defaultList(available: available) }
        let availableByID = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
        var result: [CodecPreference] = []
        var seen = Set<String>()
        for pref in stored where availableByID[pref.id] != nil {
            guard seen.insert(pref.id).inserted else { continue }
            result.append(pref)
        }
        for codec in available where !seen.contains(codec.id) {
            var pref = codec
            pref.enabled = defaultRank(mime: codec.mime, clockRate: codec.clockRate) != nil
            result.append(pref)
        }
        return result
    }
}
