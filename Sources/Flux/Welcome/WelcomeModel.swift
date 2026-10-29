import Foundation
import Observation

/// What the welcome window asks before the first space is created.
@MainActor
@Observable
final class WelcomeModel {
    enum Step: Int, CaseIterable {
        case language, welcome, space, searchEngine, passwords, done
    }

    /// Set while Flux relaunches in the language just chosen, so the welcome window picks up after
    /// that step.
    private static let languageChosenKey = "welcomeLanguageChosen"

    var step: Step
    var language: AppLanguage
    var name = String(localized: "Personal")
    var icon = ""
    var color = BrowserState.spaceColors[0]
    var searchEngine = SearchEngine.google
    /// Nil for Chromium's own password manager.
    var passwordManager: PasswordManagerExtension?

    init() {
        language = Self.shownLanguage
        step = UserDefaults.standard.bool(forKey: Self.languageChosenKey) ? .welcome : .language
    }

    static var shownLanguage: AppLanguage {
        Bundle.main.preferredLocalizations.first == AppLanguage.french.rawValue ? .french : .english
    }

    var canContinue: Bool {
        step != .space || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func goBack() {
        step = Step(rawValue: step.rawValue - 1) ?? step
    }

    /// Returns true when Flux has to relaunch to show the chosen language.
    func goForward() -> Bool {
        if step == .language, language != Self.shownLanguage {
            AppLanguage.choose(language)
            UserDefaults.standard.set(true, forKey: Self.languageChosenKey)
            return true
        }
        step = Step(rawValue: step.rawValue + 1) ?? step
        return false
    }

    func finish() {
        UserDefaults.standard.removeObject(forKey: Self.languageChosenKey)
    }
}
