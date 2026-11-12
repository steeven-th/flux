import AppKit
import Observation

/// The menu items whose shortcut can be changed in the settings, and the changes made to them.
@MainActor
@Observable
final class Shortcuts {
    private(set) static var shared: Shortcuts?

    struct Action: Identifiable {
        let id: String
        let title: String
        let menu: String
        let defaultShortcut: KeyShortcut?
        fileprivate let item: NSMenuItem
    }

    private(set) var actions: [Action] = []
    /// By action, nil for one left without a shortcut.
    private(set) var changes: [String: KeyShortcut?] = [:]
    /// Set while a shortcut is recorded, so it doesn't run its action.
    @ObservationIgnored var isRecording = false
    /// Items that keep their shortcut, like Copy, which a new one must not take.
    @ObservationIgnored private var fixedItems: [(title: String, shortcut: KeyShortcut)] = []
    @ObservationIgnored private let database: AppDatabase?

    private static let settingKey = "shortcuts"
    /// AppKit gives identifiers of its own to items it adds, like Quit and Close All Windows.
    static let identifierPrefix = "shortcut."

    static func install(in menu: NSMenu, database: AppDatabase?) {
        shared = Shortcuts(menu: menu, database: database)
    }

    private init(menu: NSMenu, database: AppDatabase?) {
        self.database = database
        for item in menu.items.compactMap(\.submenu).flatMap(\.items) where !item.isSeparatorItem {
            if let identifier = item.identifier?.rawValue, identifier.hasPrefix(Self.identifierPrefix), let menu = item.menu {
                let id = String(identifier.dropFirst(Self.identifierPrefix.count))
                actions.append(Action(id: id, title: item.title, menu: menu.title, defaultShortcut: KeyShortcut(menuItem: item), item: item))
            } else if let shortcut = KeyShortcut(menuItem: item) {
                fixedItems.append((item.title, shortcut))
            }
        }
        if let json = try? database?.setting(Self.settingKey),
           let saved = try? JSONDecoder().decode([String: KeyShortcut?].self, from: Data(json.utf8)) {
            changes = saved
        }
        actions.forEach(apply)
        FLXApplication.keyDownHandler = { [weak self] event in
            self?.handle(event) ?? false
        }
    }

    func shortcut(for action: Action) -> KeyShortcut? {
        changes[action.id] ?? action.defaultShortcut
    }

    func isChanged(_ action: Action) -> Bool {
        changes[action.id] != nil
    }

    struct Conflict {
        let owner: String
        /// False for an item that keeps its shortcut.
        let canTakeShortcut: Bool
    }

    func conflict(for shortcut: KeyShortcut, besides action: Action) -> Conflict? {
        if let other = actions.first(where: { $0.id != action.id && self.shortcut(for: $0) == shortcut }) {
            return Conflict(owner: other.title, canTakeShortcut: true)
        }
        return fixedItems.first { $0.shortcut == shortcut }.map { Conflict(owner: $0.title, canTakeShortcut: false) }
    }

    /// Another action using the shortcut is left without one.
    func set(_ shortcut: KeyShortcut?, for action: Action) {
        if let shortcut {
            for other in actions where other.id != action.id && self.shortcut(for: other) == shortcut {
                store(nil, for: other)
            }
        }
        store(shortcut, for: action)
        save()
    }

    func reset(_ action: Action) {
        changes.removeValue(forKey: action.id)
        apply(action)
        save()
    }

    func resetAll() {
        changes = [:]
        actions.forEach(apply)
        save()
    }

    private func store(_ shortcut: KeyShortcut?, for action: Action) {
        if shortcut == action.defaultShortcut {
            changes.removeValue(forKey: action.id)
        } else {
            changes.updateValue(shortcut, forKey: action.id)
        }
        apply(action)
    }

    private func apply(_ action: Action) {
        let shortcut = shortcut(for: action)
        action.item.keyEquivalent = shortcut?.key ?? ""
        action.item.keyEquivalentModifierMask = shortcut?.flags ?? []
        // A shortcut recorded is already on the user's keyboard, AppKit must not move it.
        action.item.allowsAutomaticKeyEquivalentLocalization = !isChanged(action)
    }

    private func save() {
        let json = changes.isEmpty ? nil : (try? JSONEncoder().encode(changes)).flatMap { String(data: $0, encoding: .utf8) }
        try? database?.setSetting(Self.settingKey, to: json)
    }

    /// Chromium handles these itself and never hands them to the menu: ⌘1 to ⌘9 select its own
    /// tabs, ⇧⌘C, ⌥⌘I, ⌥⌘J and ⌥⌘C open its DevTools, and ⌘. is Escape on the Mac.
    private static let keptByChromium: Set<KeyShortcut> = [
        KeyShortcut(key: "c", modifiers: [.command, .shift]),
        KeyShortcut(key: "i", modifiers: [.command, .option]),
        KeyShortcut(key: "j", modifiers: [.command, .option]),
        KeyShortcut(key: "c", modifiers: [.command, .option]),
        KeyShortcut(key: ".", modifiers: .command),
    ]

    private static func isKeptByChromium(_ shortcut: KeyShortcut) -> Bool {
        shortcut.isDigit || keptByChromium.contains(shortcut)
    }

    /// Shortcuts the menu can't match, or that Chromium keeps, are matched on the key before
    /// Chromium sees them. Others are left to the menu, which only gets them after the page, so a
    /// web app can still use them.
    private func handle(_ event: NSEvent) -> Bool {
        guard !isRecording else { return false }
        let pressed = KeyShortcut(event: event).map { [$0] } ?? []
        let typed = KeyShortcut(typedBy: event).map { [$0] } ?? []
        let candidates = pressed.filter { $0.needsKeyMatching || Self.isKeptByChromium($0) } + typed.filter(Self.isKeptByChromium)
        guard let action = actions.first(where: { action in candidates.contains { $0 == shortcut(for: action) } }),
              let menu = action.item.menu else {
            return false
        }
        menu.update()
        guard action.item.isEnabled else { return false }
        menu.performActionForItem(at: menu.index(of: action.item))
        return true
    }
}
