import Foundation

/// One captured SIP message (request or response), extracted from the SIP
/// stack's log stream.
public struct SIPTraceEntry: Identifiable, Equatable, Sendable {
    public enum Direction: String, Sendable {
        case sent, received, unknown
    }

    public let id: UUID
    public let date: Date
    public let direction: Direction
    /// Request line or status line, e.g. "INVITE sip:600@… SIP/2.0".
    public let firstLine: String
    /// The complete SIP message, headers and body.
    public let raw: String
    /// Audio codecs from the SDP body, when the message carries one.
    public let sdp: SDPAudioDescription?

    public init(
        id: UUID = UUID(), date: Date, direction: Direction,
        firstLine: String, raw: String, sdp: SDPAudioDescription?
    ) {
        self.id = id
        self.date = date
        self.direction = direction
        self.firstLine = firstLine
        self.raw = raw
        self.sdp = sdp
    }

    public var isRequest: Bool { !firstLine.hasPrefix("SIP/2.0") }

    /// "INVITE", "REGISTER", … for requests; "200 OK", "486 Busy Here", …
    /// for responses. Used for compact display and filtering.
    public var label: String {
        if isRequest {
            return firstLine.split(separator: " ").first.map(String.init) ?? firstLine
        }
        return firstLine.replacingOccurrences(of: "SIP/2.0 ", with: "")
    }
}

/// Extracts SIP messages from belle-sip's log lines. A message log looks like
///
///     channel [0x…]: message received from [UDP://127.0.0.1:5060], size: [520] bytes:
///     SIP/2.0 200 OK
///     Via: …
///
/// Anything without a SIP start-line is ignored.
public enum SIPTraceParser {
    private static let methods = [
        "INVITE ", "ACK ", "BYE ", "CANCEL ", "REGISTER ", "OPTIONS ",
        "INFO ", "UPDATE ", "PRACK ", "SUBSCRIBE ", "NOTIFY ", "REFER ",
        "MESSAGE ", "PUBLISH ",
    ]

    /// Returns nil when the log message contains no SIP message.
    public static func parse(logMessage: String, date: Date = Date()) -> SIPTraceEntry? {
        let lines = logMessage.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard let startIndex = lines.firstIndex(where: { isStartLine($0) }) else { return nil }

        let direction: SIPTraceEntry.Direction
        let preamble = lines[..<startIndex].joined(separator: "\n")
        if preamble.contains("message received") || preamble.contains("received from") {
            direction = .received
        } else if preamble.contains("message sent") || preamble.contains("sent to") {
            direction = .sent
        } else {
            direction = .unknown
        }

        let message = lines[startIndex...].joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = String(lines[startIndex]).trimmingCharacters(in: .whitespaces)
        let sdp = message.contains("m=audio") ? SDPAudioDescription.parse(message) : nil

        return SIPTraceEntry(
            date: date, direction: direction,
            firstLine: firstLine, raw: message, sdp: sdp)
    }

    static func isStartLine<S: StringProtocol>(_ line: S) -> Bool {
        if line.hasPrefix("SIP/2.0 ") { return true }
        return methods.contains { line.hasPrefix($0) } && line.hasSuffix("SIP/2.0")
    }
}
