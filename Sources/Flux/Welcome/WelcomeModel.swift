import Foundation
import Observation

/// What the welcome window asks before the first space is created.
@MainActor
@Observable
final class WelcomeModel {
    enum Step: Int, CaseIterable {
        case welcome, imports, space, searchEngine, passwords, done
    }

    var step = Step.welcome
    /// The browsers installed that Flux imports from, with their spaces, for the step offering to
    /// bring them.
    private(set) var sources: [(source: ImportSource, spaces: [ImportedSpace])] = []
    /// Installed browsers whose data macOS doesn't let Flux read yet: it asks the user the first
    /// time, and Flux reads them again until it may.
    private(set) var waitingSources: [ImportSource] = []
    /// Nil to start with a new space.
    var importSource: ImportSource?
    var importsToday = false
    @ObservationIgnored private var retry: Timer?
    private let installedSources = ImportSource.allCases.filter(\.isAvailable)

    init() {
        readSources()
        importSource = sources.first?.source
    }

    private func readSources() {
        var read: [(source: ImportSource, spaces: [ImportedSpace])] = []
        var waiting: [ImportSource] = []
        for source in installedSources {
            do {
                let spaces = try source.loadSpaces()
                if !spaces.isEmpty { read.append((source, spaces)) }
            } catch {
                waiting.append(source)
            }
        }
        sources = read
        waitingSources = waiting
        if waiting.isEmpty {
            retry?.invalidate()
            retry = nil
        } else if retry == nil {
            retry = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.readSources() }
            }
        }
    }

    var importedSpaces: [ImportedSpace] {
        sources.first { $0.source == importSource }?.spaces ?? []
    }
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
        if isSkipped(step) { goBack() }
    }

    func goForward() {
        step = Step(rawValue: step.rawValue + 1) ?? step
        if isSkipped(step) { goForward() }
    }

    /// Without another browser there is nothing to import. Its spaces replace the first space's
    /// step, and bring their passwords and, among their extensions, their password manager.
    private func isSkipped(_ step: Step) -> Bool {
        switch step {
        case .imports: installedSources.isEmpty
        case .space, .passwords: importSource != nil
        default: false
        }
    }
}
