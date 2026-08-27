import Foundation

/// Where a number to be dialed originated. Determines whether the outside-line
/// prefix is applied: numbers composed inside the app (dialpad, internal
/// contacts) are dialed verbatim; everything else is assumed to be an outside
/// line and gets the account's prefix.
public enum NumberOrigin: Sendable, Equatable {
    /// Typed on the in-app dialpad. Dialed verbatim.
    case dialpad
    /// One of Sippy's own contacts (PBX extensions and friends). Dialed verbatim.
    case internalContact
    /// A number from the system address book. Prefixed.
    case systemContact
    /// tel:/callto:/sip: URL, Services menu, paste-and-dial. Prefixed.
    case external
}

/// Per-account dialing rules applied before a number reaches the SIP stack.
public struct DialPlan: Sendable, Equatable {
    /// Prepended to numbers from prefixed origins. Arbitrary string, e.g. "0",
    /// "9" or "0*4". Empty string disables prefixing.
    public var outsideLinePrefix: String

    /// Replacement for a leading "+" (e.g. "00" in Europe, "011" in NANP).
    /// nil leaves the "+" untouched (many PBXs accept it).
    public var internationalPrefix: String?

    public init(outsideLinePrefix: String = "", internationalPrefix: String? = nil) {
        self.outsideLinePrefix = outsideLinePrefix
        self.internationalPrefix = internationalPrefix
    }

    /// Characters that survive normalization. Everything else (spaces, dashes,
    /// parentheses, dots — the usual formatting noise) is stripped.
    private static let dialable = Set("0123456789*#+")

    /// Strips formatting, applies the international rewrite, and prepends the
    /// outside-line prefix when the origin calls for it.
    public func apply(to raw: String, origin: NumberOrigin) -> String {
        var number = String(raw.filter { Self.dialable.contains($0) })

        if let internationalPrefix, number.hasPrefix("+") {
            number = internationalPrefix + number.dropFirst()
        }

        switch origin {
        case .dialpad, .internalContact:
            return number
        case .systemContact, .external:
            return outsideLinePrefix + number
        }
    }
}
