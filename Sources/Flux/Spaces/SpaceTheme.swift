import AppKit
import SwiftUI

/// How a space tints the window. Kept as JSON in the space's record, next to its main color, so
/// themes can grow without a migration each time.
struct SpaceTheme: Codable, Hashable {
    static let defaultTint = 0.12
    static let tintRange = 0.04...0.45
    static let maxColors = 3
    static let defaultAngle = 45.0

    /// "#RRGGBB". The first one is the space's color, for its icon and accents. With more, the
    /// window shows a gradient of them.
    var colors: [String]
    /// Opacity of the tint over the window's background.
    var tint = Self.defaultTint
    /// Direction of the gradient in degrees, clockwise from left to right.
    var angle = Self.defaultAngle
    var appearance = Appearance.system
    /// How much film grain covers the tint, from none to 1.
    var grain = 0.0
    /// An SF Symbol shown instead of the emoji. Kept here, so older versions of Flux show the
    /// space's initial rather than the symbol's name.
    var symbol: String?

    /// Light or dark for the window. Pages keep following the Mac, as in Arc.
    enum Appearance: String, Codable, CaseIterable {
        case system, light, dark

        var nsAppearance: NSAppearance? {
            switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
    }

    init(colors: [String], tint: Double = Self.defaultTint, angle: Double = Self.defaultAngle) {
        self.colors = colors
        self.tint = tint
        self.angle = angle
    }

    init(color: String, tint: Double = Self.defaultTint) {
        self.init(colors: [color], tint: tint)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        colors = try container.decodeIfPresent([String].self, forKey: .colors) ?? []
        tint = try container.decodeIfPresent(Double.self, forKey: .tint) ?? Self.defaultTint
        angle = try container.decodeIfPresent(Double.self, forKey: .angle) ?? Self.defaultAngle
        appearance = (try? container.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? .system
        grain = try container.decodeIfPresent(Double.self, forKey: .grain) ?? 0
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
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
        theme.colors = Array(theme.colors.prefix(Self.maxColors))
        theme.tint = min(max(theme.tint, Self.tintRange.lowerBound), Self.tintRange.upperBound)
        theme.grain = min(max(theme.grain, 0), 1)
        return theme
    }

    var json: String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// A color for the gradient that goes with the others: the next hue along.
    func nextColor() -> String {
        let last = NSColor(Color(hex: colors.last ?? color)).usingColorSpace(.sRGB) ?? .gray
        let hue = (last.hueComponent + .random(in: 0.08...0.16)).truncatingRemainder(dividingBy: 1)
        return NSColor(
            hue: hue, saturation: max(last.saturationComponent, 0.4),
            brightness: max(last.brightnessComponent, 0.7), alpha: 1
        ).hexString
    }

    /// Colors that go together: lively hues close to each other, never too dark nor too pale, and
    /// a tint that keeps text easy to read.
    static func random() -> SpaceTheme {
        let first = NSColor(
            hue: .random(in: 0..<1), saturation: .random(in: 0.5...0.8),
            brightness: .random(in: 0.75...0.95), alpha: 1
        )
        var theme = SpaceTheme(color: first.hexString, tint: .random(in: 0.1...0.25))
        for _ in 1..<Int.random(in: 1...maxColors) { theme.colors.append(theme.nextColor()) }
        theme.angle = [0, 45, 90, 135, 180, 225, 270, 315].randomElement()!
        return theme
    }

    /// New colors, keeping the appearance and the grain, which are a matter of taste more than of
    /// colors.
    mutating func shuffle() {
        let random = Self.random()
        colors = random.colors
        tint = random.tint
        angle = random.angle
    }
}

/// The space's look behind the window: its color, or the gradient of its colors, and its grain.
struct SpaceTint: View {
    let theme: SpaceTheme

    var body: some View {
        ZStack {
            colors
            if theme.grain > 0 {
                Image(nsImage: Self.grain)
                    .resizable(resizingMode: .tile)
                    .opacity(theme.grain * 0.14)
            }
        }
    }

    @ViewBuilder
    private var colors: some View {
        if theme.colors.count > 1 {
            let radians = theme.angle * .pi / 180
            let dx = cos(radians) / 2, dy = sin(radians) / 2
            LinearGradient(
                colors: theme.colors.map(Color.init(hex:)),
                startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
                endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)
            )
            .opacity(theme.tint)
        } else {
            Color(hex: theme.color).opacity(theme.tint)
        }
    }

    /// Gray noise, one pixel per grain on a Retina screen.
    private static let grain: NSImage = {
        let side = 128
        let pixels = Data((0..<side * side).map { _ in UInt8.random(in: 0...255) })
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                  width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(), provider: provider,
                  decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else { return NSImage() }
        return NSImage(cgImage: image, size: NSSize(width: side / 2, height: side / 2))
    }()
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
