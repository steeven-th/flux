import Foundation

/// How long a loaded tab can stay unseen before its page is unloaded to free its memory.
enum TabSleepDelay: String, CaseIterable, Identifiable {
    case fifteenMinutes = "15m"
    case thirtyMinutes = "30m"
    case oneHour = "1h"
    case twoHours = "2h"
    case never

    static let standard = TabSleepDelay.oneHour

    var id: Self { self }

    var interval: TimeInterval? {
        switch self {
        case .fifteenMinutes: 15 * 60
        case .thirtyMinutes: 30 * 60
        case .oneHour: 3600
        case .twoHours: 2 * 3600
        case .never: nil
        }
    }

    var name: String {
        switch self {
        case .fifteenMinutes: String(localized: "15 minutes")
        case .thirtyMinutes: String(localized: "30 minutes")
        case .oneHour: String(localized: "1 hour")
        case .twoHours: String(localized: "2 hours")
        case .never: String(localized: "Never")
        }
    }
}
