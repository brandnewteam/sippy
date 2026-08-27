import Foundation

/// Minimal SDP reader for the codec-negotiation view: extracts the audio
/// media description's codec list (payload numbers → rtpmap names), in offer
/// order. Pure string parsing, no SIP dependency.
public struct SDPAudioDescription: Equatable, Sendable {
    public struct Codec: Equatable, Sendable {
        public var payloadNumber: Int
        /// e.g. "opus/48000/2"; resolved from a=rtpmap or the static RTP table.
        public var name: String
        public var fmtp: String?

        public init(payloadNumber: Int, name: String, fmtp: String? = nil) {
            self.payloadNumber = payloadNumber
            self.name = name
            self.fmtp = fmtp
        }
    }

    public var codecs: [Codec]

    /// Static payload types (RFC 3551) that need no a=rtpmap line.
    static let staticPayloads: [Int: String] = [
        0: "PCMU/8000", 3: "GSM/8000", 4: "G723/8000", 8: "PCMA/8000",
        9: "G722/8000", 18: "G729/8000",
    ]

    /// Parses the first `m=audio` section of an SDP body. Returns nil if the
    /// text contains no audio media line.
    public static func parse(_ sdp: String) -> SDPAudioDescription? {
        var payloadOrder: [Int]?
        var rtpmap: [Int: String] = [:]
        var fmtp: [Int: String] = [:]
        var inAudioSection = false

        for rawLine in sdp.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("m=") {
                if inAudioSection { break }  // next media section: stop
                if line.hasPrefix("m=audio") {
                    inAudioSection = true
                    // m=audio 7078 RTP/AVP 96 0 8 18 101
                    let fields = line.split(separator: " ").dropFirst(3)
                    payloadOrder = fields.compactMap { Int($0) }
                }
                continue
            }
            guard inAudioSection else { continue }
            if line.hasPrefix("a=rtpmap:") {
                // a=rtpmap:96 opus/48000/2
                let body = line.dropFirst("a=rtpmap:".count)
                if let space = body.firstIndex(of: " "), let number = Int(body[..<space]) {
                    rtpmap[number] = String(body[body.index(after: space)...])
                        .trimmingCharacters(in: .whitespaces)
                }
            } else if line.hasPrefix("a=fmtp:") {
                // a=fmtp:18 annexb=no
                let body = line.dropFirst("a=fmtp:".count)
                if let space = body.firstIndex(of: " "), let number = Int(body[..<space]) {
                    fmtp[number] = String(body[body.index(after: space)...])
                        .trimmingCharacters(in: .whitespaces)
                }
            }
        }

        guard let payloadOrder else { return nil }
        let codecs = payloadOrder.map { number in
            Codec(
                payloadNumber: number,
                name: rtpmap[number] ?? staticPayloads[number] ?? "dynamic(\(number))",
                fmtp: fmtp[number])
        }
        return SDPAudioDescription(codecs: codecs)
    }
}
