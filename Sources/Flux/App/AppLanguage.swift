import Foundation

/// The language Flux shows in. Set like the per-app language of System Settings, through
/// AppleLanguages in Flux's own defaults, which macOS and Chromium only read at launch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case french = "fr"

    var id: Self { self }

    /// Each language is named in itself, so it can be found whatever the current one.
    var name: String {
        switch self {
        case .system: String(localized: "System")
        case .english: "English"
        case .french: "Français"
        }
    }

    static var current: AppLanguage {
        guard let domain = Bundle.main.bundleIdentifier,
              let languages = UserDefaults.standard.persistentDomain(forName: domain)?["AppleLanguages"] as? [String],
              let first = languages.first else { return .system }
        return AppLanguage(rawValue: String(first.prefix(2))) ?? .system
    }

    static func choose(_ language: AppLanguage) {
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
    }
}
