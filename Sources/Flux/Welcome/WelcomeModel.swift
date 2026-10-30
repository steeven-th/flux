import Foundation
import Observation

/// What the welcome window asks before the first space is created.
@MainActor
@Observable
final class WelcomeModel {
    enum Step: Int, CaseIterable {
        case welcome, space, searchEngine, passwords, done
    }

    var step = Step.welcome
    var name = String(localized: "Personal")
    var icon = ""
    var color = BrowserState.spaceColors[0]
    var searchEngine = SearchEngine.google
    /// Nil for Chromium's own password manager.
    var passwordManager: PasswordManagerExtension?

    var canContinue: Bool {
        step != .space || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func goBack() {
        step = Step(rawValue: step.rawValue - 1) ?? step
    }

    func goForward() {
        step = Step(rawValue: step.rawValue + 1) ?? step
    }
}
