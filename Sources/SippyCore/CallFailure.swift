import Foundation

/// Builds the user-facing description of a failed call from the protocol
/// error the peer sent: the SIP status line ("480 Temporarily Unavailable")
/// plus, when present, the Reason header a PBX attaches to say *why*
/// (e.g. "Q.850 cause 21"). Pure so it can be tested without the SIP stack.
public enum CallFailureFormatter {
    /// - Parameters:
    ///   - stackMessage: the SIP stack's own summary of the state change;
    ///     the fallback when no protocol error is available.
    ///   - proto: protocol name of the error response (usually "SIP").
    ///   - code: status code of the error response; 0 means none.
    ///   - phrase: reason phrase from the response's status line.
    ///   - reasonProtocol/reasonCode/reasonPhrase: the response's Reason
    ///     header, when the peer sent one.
    public static func describe(
        stackMessage: String,
        proto: String?,
        code: Int,
        phrase: String?,
        reasonProtocol: String? = nil,
        reasonCode: Int = 0,
        reasonPhrase: String? = nil
    ) -> String {
        let fallback = stackMessage.isEmpty ? "Call failed." : stackMessage
        guard code != 0 else { return fallback }

        let proto = normalized(proto) ?? "SIP"
        var text = "\(proto) \(code)"
        if let phrase = normalized(phrase) {
            text += " \(phrase)"
        } else if !stackMessage.isEmpty {
            text += " \(stackMessage)"
        }

        if let reason = reasonText(
            mainProto: proto, mainCode: code, mainPhrase: normalized(phrase),
            proto: normalized(reasonProtocol), code: reasonCode,
            phrase: normalized(reasonPhrase)) {
            text += " — \(reason)"
        }
        return text
    }

    /// The Reason-header part, or nil when it adds nothing over the status
    /// line (PBXs often mirror it: "Reason: SIP;cause=480").
    private static func reasonText(
        mainProto: String, mainCode: Int, mainPhrase: String?,
        proto: String?, code: Int, phrase: String?
    ) -> String? {
        guard proto != nil || code != 0 || phrase != nil else { return nil }
        let sameStatus = (proto ?? mainProto).caseInsensitiveCompare(mainProto) == .orderedSame
            && code == mainCode
        if sameStatus, phrase == nil || phrase?.caseInsensitiveCompare(mainPhrase ?? "") == .orderedSame {
            return nil
        }
        var parts: [String] = []
        if let proto { parts.append(proto) }
        if code != 0 { parts.append("cause \(code)") }
        if let phrase { parts.append(phrase) }
        return "Reason: " + parts.joined(separator: " ")
    }

    private static func normalized(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}
