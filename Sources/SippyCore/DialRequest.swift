import Foundation

/// What an external open-URL / service invocation asks Sippy to dial.
public enum DialRequest: Equatable {
    /// A bare number ("0612345678", "124") — goes through the dial plan with
    /// origin `.external` (outside-line prefix applies).
    case number(String)
    /// A full SIP URI with a host part — dialed as-is, no rewriting.
    case uri(String)

    /// Parses tel:, callto: and sip:/sips: URLs. Accepts the sloppy forms
    /// real apps produce: "tel:+39 06 123", "tel://0612345678",
    /// "callto:0612345678", "sip:124", "sip:user@host;params".
    public static func parse(_ url: URL) -> DialRequest? {
        guard let scheme = url.scheme?.lowercased() else { return nil }

        // Strip "<scheme>:" and any authority slashes, then percent-decode.
        var rest = String(url.absoluteString.dropFirst(scheme.count + 1))
        while rest.hasPrefix("/") { rest.removeFirst() }
        rest = rest.removingPercentEncoding ?? rest
        guard !rest.isEmpty else { return nil }

        switch scheme {
        case "tel", "callto":
            // Drop URI parameters (";phone-context=…") before normalizing.
            let bare = rest.split(separator: ";", maxSplits: 1)[0]
            let number = PhoneNumberMatcher.normalize(String(bare))
            return number.isEmpty ? nil : .number(number)
        case "sip", "sips":
            if rest.contains("@") {
                return .uri("\(scheme):\(rest)")
            }
            // Host-less sip URI ("sip:124") is just a number for our account.
            let bare = rest.split(separator: ";", maxSplits: 1)[0]
            let number = PhoneNumberMatcher.normalize(String(bare))
            return number.isEmpty ? nil : .number(number)
        default:
            return nil
        }
    }

    /// Parses free text (Services menu, paste-and-dial): a URL if it looks
    /// like one, otherwise a number.
    public static func parse(text: String) -> DialRequest? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           ["tel", "callto", "sip", "sips"].contains(scheme) {
            return parse(url)
        }
        let number = PhoneNumberMatcher.normalize(trimmed)
        return number.isEmpty ? nil : .number(number)
    }
}
