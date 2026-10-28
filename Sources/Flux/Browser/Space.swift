import SwiftUI

struct Space: Identifiable, Hashable {
    let id: UUID
    var name: String
    var icon: String?
    /// "#RRGGBB"
    var colorHex: String
    /// The Chromium profile folder. Several spaces can share one.
    var profileFolder: URL

    init(record: SpaceRecord) {
        id = record.id
        name = record.name
        icon = record.icon
        colorHex = record.color
        profileFolder = AppPaths.profileFolder(named: record.profileFolder)
    }

    var color: Color {
        Color(hex: colorHex)
    }
}

extension Color {
    /// Parses "#RRGGBB". Anything else gives gray.
    init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = .gray
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
