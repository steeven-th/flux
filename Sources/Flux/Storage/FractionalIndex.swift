/// Sort keys that always leave room between two neighbors, so moving an item only rewrites that
/// item. Keys are base 62 fractions compared as plain strings.
enum FractionalIndex {
    private static let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

    /// A key sorting strictly between `before` and `after`. Nil means no neighbor on that side.
    static func between(_ before: String?, _ after: String?) -> String {
        let lower = before.map(Array.init) ?? []
        let upper = after.map(Array.init)
        if let upper {
            precondition(lower.lexicographicallyPrecedes(upper), "keys out of order")
        }
        return String(midpoint(lower, upper))
    }

    private static func midpoint(_ lower: [Character], _ upper: [Character]?) -> [Character] {
        if let upper {
            var shared = 0
            while shared < upper.count, (shared < lower.count ? lower[shared] : "0") == upper[shared] {
                shared += 1
            }
            if shared > 0 {
                return Array(upper.prefix(shared))
                    + midpoint(Array(lower.dropFirst(shared)), Array(upper.dropFirst(shared)))
            }
        }
        let low = lower.first.map(value) ?? 0
        let high = upper?.first.map(value) ?? digits.count
        // The first key sits in the middle, leaving room on both sides. At either end of a list,
        // keys step by one digit rather than halving the gap: halving would make them grow by a
        // character every few additions, and adding at the end is the common case.
        if lower.isEmpty, upper == nil {
            return [digits[digits.count / 2]]
        }
        if upper == nil, low + 1 < high {
            return [digits[low + 1]]
        }
        if lower.isEmpty, let upper {
            if high > 1 {
                return [digits[high - 1]]
            }
            if upper.count == 1 {
                return [digits[0], digits[digits.count - 1]]
            }
        }
        if high - low > 1 {
            return [digits[(low + high) / 2]]
        }
        if let upper, upper.count > 1 {
            return [upper[0]]
        }
        return [digits[low]] + midpoint(Array(lower.dropFirst()), nil)
    }

    private static func value(of digit: Character) -> Int {
        digits.firstIndex(of: digit)!
    }
}
