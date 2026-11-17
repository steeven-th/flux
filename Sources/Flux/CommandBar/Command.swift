import AppKit

/// Something the command bar can do: an item of Flux's menus, or an action on the selected tab
/// that only the sidebar or the page menu offers.
struct Command: Identifiable {
    let id: String
    let title: String
    /// The menu it comes from, shown next to it.
    let place: String
    let shortcut: String?
    let perform: @MainActor () -> Void

    /// The ones that open the command bar themselves.
    private static let excluded: Set<Selector> = [
        #selector(AppDelegate.newTab(_:)), #selector(AppDelegate.openLocation(_:)),
    ]

    /// What can be done now, as the menus would offer it.
    @MainActor
    static func available(in state: BrowserState) -> [Command] {
        menuCommands() + tabCommands(in: state)
    }

    @MainActor
    private static func menuCommands() -> [Command] {
        guard let delegate = AppDelegate.shared, let mainMenu = NSApp.mainMenu else { return [] }
        var commands: [Command] = []
        func add(_ menu: NSMenu, place: String) {
            // The Spaces menu names its items after the spaces when it opens.
            menu.delegate?.menuNeedsUpdate?(menu)
            for item in menu.items where !item.isHidden && !item.isSeparatorItem {
                if let submenu = item.submenu {
                    add(submenu, place: item.title)
                    continue
                }
                guard let action = item.action, item.target === delegate, !excluded.contains(action),
                      delegate.validateMenuItem(item) else { continue }
                commands.append(Command(
                    id: "menu:\(NSStringFromSelector(action)):\(item.tag)", title: item.title, place: place,
                    shortcut: KeyShortcut(menuItem: item)?.displayName
                ) { [weak delegate, weak item] in
                    NSApp.sendAction(action, to: delegate, from: item)
                })
            }
        }
        for item in mainMenu.items {
            guard let submenu = item.submenu else { continue }
            add(submenu, place: item.title.isEmpty ? "Flux" : item.title)
        }
        return commands
    }

    @MainActor
    private static func tabCommands(in state: BrowserState) -> [Command] {
        guard let tab = state.selectedTab else { return [] }
        let place = String(localized: "Tab")
        var commands: [Command] = []
        if tab.node.section == .today {
            commands.append(Command(id: "tab:favorite", title: String(localized: "Add to Favorites"), place: place, shortcut: nil) {
                state.moveToFavorites(tab)
            })
        } else if tab.node.section == .favorites {
            commands.append(Command(id: "tab:today", title: String(localized: "Move to Today"), place: place, shortcut: nil) {
                state.moveToToday(tab)
            })
        }
        guard URL(string: tab.url)?.host() != nil else { return commands }
        let isDeveloperMode = state.isDeveloperMode(for: tab.url)
        commands.append(Command(
            id: "tab:developer",
            title: isDeveloperMode ? String(localized: "Turn Off Developer Mode") : String(localized: "Turn On Developer Mode"),
            place: place, shortcut: nil
        ) {
            state.setDeveloperMode(!isDeveloperMode, for: tab.url)
        })
        commands.append(Command(id: "tab:cache", title: String(localized: "Clear Site Cache"), place: place, shortcut: nil) {
            ReloadOnce.after(tab.browserView.clearSiteCache, page: tab.browserView)
        })
        return commands
    }

    /// 2 when a word of the title starts with the text, 1 when the title or the menu only
    /// contains it.
    func relevance(to text: String) -> Int {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let words = title.split { !$0.isLetter && !$0.isNumber }
        if title.range(of: text, options: options.union(.anchored)) != nil
            || words.contains(where: { $0.range(of: text, options: options.union(.anchored)) != nil }) {
            return 2
        }
        return title.range(of: text, options: options) != nil || place.range(of: text, options: options) != nil ? 1 : 0
    }
}
