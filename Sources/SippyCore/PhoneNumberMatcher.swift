import Foundation

/// Matching between dialed/incoming numbers and stored contact numbers.
/// Stored numbers carry formatting and country prefixes that the wire format
/// lacks, so equality is decided on normalized forms with a suffix fallback.
public enum PhoneNumberMatcher {
    private static let dialable = Set("0123456789*#+")

    /// Strips formatting noise: "+39 06 1234-5678" → "+390612345678".
    public static func normalize(_ raw: String) -> String {
        String(raw.filter { dialable.contains($0) })
    }

    /// Significant digits only — drops "+" and international/trunk prefixes'
    /// visual differences by comparing digit tails.
    private static func digits(_ raw: String) -> String {
        String(raw.filter(\.isNumber))
    }

    /// True when the two numbers plausibly denote the same line: normalized
    /// equality, or one digit-string is a suffix of the other with at least
    /// `minSuffix` digits (so "+390612345678" matches "0612345678", while
    /// short PBX extensions still require an exact match).
    public static func matches(_ a: String, _ b: String, minSuffix: Int = 7) -> Bool {
        let na = normalize(a), nb = normalize(b)
        guard !na.isEmpty, !nb.isEmpty else { return false }
        if na == nb { return true }
        let da = digits(na), db = digits(nb)
        if da == db { return !da.isEmpty }
        guard min(da.count, db.count) >= minSuffix else { return false }
        return da.hasSuffix(db) || db.hasSuffix(da)
    }
}
