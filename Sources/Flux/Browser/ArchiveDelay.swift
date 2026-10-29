import Foundation

/// How long a tab of Today can stay unseen before it is archived.
enum ArchiveDelay: String, CaseIterable, Identifiable {
    case twelveHours = "12h"
    case oneDay = "24h"
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case never

    static let standard = ArchiveDelay.oneDay

    var id: Self { self }

    var interval: TimeInterval? {
        switch self {
        case .twelveHours: 12 * 3600
        case .oneDay: 24 * 3600
        case .sevenDays: 7 * 86_400
        case .thirtyDays: 30 * 86_400
        case .never: nil
        }
    }

    var name: String {
        switch self {
        case .twelveHours: String(localized: "12 hours")
        case .oneDay: String(localized: "24 hours")
        case .sevenDays: String(localized: "7 days")
        case .thirtyDays: String(localized: "30 days")
        case .never: String(localized: "Never")
        }
    }
}
