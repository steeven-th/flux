import AppKit
import SwiftUI

/// How a space tints the window. Kept as JSON in the space's record, next to its main color, so
/// themes can grow without a migration each time.
struct SpaceTheme: Codable, Hashable {
    static let defaultTint = 0.12
    static let tintRange = 0.04...0.45

    /// "#RRGGBB". The first one is the space's color, for its icon and accents.
    var colors: [String]
    /// Opacity of the tint over the window's background.
    var tint = Self.defaultTint

    init(color: String, tint: Double = Self.defaultTint) {
        colors = [color]
        self.tint = tint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        colors = try container.decodeIfPresent([String].self, forKey: .colors) ?? []
        tint = try container.decodeIfPresent(Double.self, forKey: .tint) ?? Self.defaultTint
    }

    var color: String {
        get { colors.first ?? "#808080" }
        set {
            if colors.isEmpty { colors = [newValue] } else { colors[0] = newValue }
        }
    }

    /// The space's record keeps its color apart, for older versions of Flux, and its theme only
    /// once it was customized.
    static func decoded(_ json: String?, color: String) -> SpaceTheme {
        var theme = json.flatMap { try? JSONDecoder().decode(SpaceTheme.self, from: Data($0.utf8)) }
            ?? SpaceTheme(color: color)
        theme.color = color
        theme.tint = min(max(theme.tint, Self.tintRange.lowerBound), Self.tintRange.upperBound)
        return theme
    }

    var json: String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Colors that go together: a lively hue, never too dark nor too pale, and a tint that keeps
    /// text easy to read.
    static func random() -> SpaceTheme {
        let color = NSColor(
            hue: .random(in: 0..<1), saturation: .random(in: 0.5...0.8),
            brightness: .random(in: 0.75...0.95), alpha: 1
        )
        return SpaceTheme(color: color.hexString, tint: .random(in: 0.1...0.25))
    }
}

extension NSColor {
    /// "#RRGGBB" in sRGB.
    var hexString: String {
        let color = usingColorSpace(.sRGB) ?? self
        func component(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(
            format: "#%02X%02X%02X",
            component(color.redComponent), component(color.greenComponent), component(color.blueComponent)
        )
    }
}
