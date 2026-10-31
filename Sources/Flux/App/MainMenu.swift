import AppKit

@MainActor
enum MainMenu {
    /// `spacesMenuDelegate` fills in the spaces' names each time the Spaces menu opens.
    static func make(spacesMenuDelegate: NSMenuDelegate) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu(title: String(localized: "Flux"), items: customizable([
            NSMenuItem(title: String(localized: "Settings…"), action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ","),
            .separator(),
            shifted(NSMenuItem(title: String(localized: "Extensions…"), action: #selector(AppDelegate.showExtensions(_:)), keyEquivalent: "e")),
            NSMenuItem(title: String(localized: "Passwords…"), action: #selector(AppDelegate.showPasswords(_:)), keyEquivalent: ""),
        ]) + [
            .separator(),
            NSMenuItem(title: String(localized: "Quit Flux"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]))
        menu.addItem(submenu(title: String(localized: "File"), items: customizable([
            NSMenuItem(title: String(localized: "New Tab"), action: #selector(AppDelegate.newTab(_:)), keyEquivalent: "t"),
            NSMenuItem(title: String(localized: "Open Location…"), action: #selector(AppDelegate.openLocation(_:)), keyEquivalent: "l"),
            NSMenuItem(title: String(localized: "Close Tab"), action: #selector(AppDelegate.closeTab(_:)), keyEquivalent: "w"),
            NSMenuItem(title: String(localized: "Pin or Unpin Tab"), action: #selector(AppDelegate.togglePin(_:)), keyEquivalent: "d"),
            NSMenuItem(title: String(localized: "New Folder"), action: #selector(AppDelegate.newFolder(_:)), keyEquivalent: ""),
            NSMenuItem(title: String(localized: "Open in Space"), action: #selector(AppDelegate.openLittleWindowInSpace(_:)), keyEquivalent: "o"),
            .separator(),
            NSMenuItem(title: String(localized: "Import from Another Browser…"), action: #selector(AppDelegate.importFromBrowser(_:)), keyEquivalent: ""),
        ])))
        menu.addItem(submenu(title: String(localized: "Edit"), items: [
            NSMenuItem(title: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z"),
            shifted(NSMenuItem(title: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "z")),
            .separator(),
            NSMenuItem(title: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ]))
        menu.addItem(submenu(title: String(localized: "View"), items: customizable([
            NSMenuItem(title: String(localized: "Toggle Sidebar"), action: #selector(AppDelegate.showOrHideSidebar(_:)), keyEquivalent: "s"),
            .separator(),
            controlShift(NSMenuItem(title: String(localized: "Add Split View"), action: #selector(AppDelegate.addSplitPane(_:)), keyEquivalent: "=")),
            controlShift(NSMenuItem(title: String(localized: "Close Split Pane"), action: #selector(AppDelegate.closeSplitPane(_:)), keyEquivalent: "-")),
            .separator(),
            NSMenuItem(title: String(localized: "Reload Page"), action: #selector(AppDelegate.reloadPage(_:)), keyEquivalent: "r"),
            shifted(NSMenuItem(title: String(localized: "Reload Ignoring Cache"), action: #selector(AppDelegate.reloadPageIgnoringCache(_:)), keyEquivalent: "r")),
            NSMenuItem(title: String(localized: "Back"), action: #selector(AppDelegate.goBack(_:)), keyEquivalent: "["),
            NSMenuItem(title: String(localized: "Forward"), action: #selector(AppDelegate.goForward(_:)), keyEquivalent: "]"),
        ])))
        menu.addItem(submenu(title: String(localized: "History"), items: customizable([
            NSMenuItem(title: String(localized: "Show All History"), action: #selector(AppDelegate.showHistory(_:)), keyEquivalent: "y"),
            shifted(NSMenuItem(title: String(localized: "Show Archive"), action: #selector(AppDelegate.showArchive(_:)), keyEquivalent: "a")),
            optionCommand(NSMenuItem(title: String(localized: "Show Downloads"), action: #selector(AppDelegate.showLibrary(_:)), keyEquivalent: "l")),
            shifted(NSMenuItem(
                title: String(localized: "Clear Browsing Data…"), action: #selector(AppDelegate.clearBrowsingData(_:)), keyEquivalent: "\u{8}"
            )),
        ])))
        menu.addItem(spacesMenu(delegate: spacesMenuDelegate))
        menu.addItem(submenu(title: String(localized: "Debug"), items: [
            NSMenuItem(title: String(localized: "Open Tab in Chrome Window"), action: #selector(AppDelegate.openInChromeWindow(_:)), keyEquivalent: ""),
            NSMenuItem(title: String(localized: "Show Welcome Window"), action: #selector(AppDelegate.previewWelcome(_:)), keyEquivalent: ""),
        ]))
        return menu
    }

    /// ⌃1 to ⌃9 select the first nine spaces. The items exist up front so the shortcuts work
    /// without opening the menu.
    private static func spacesMenu(delegate: NSMenuDelegate) -> NSMenuItem {
        let items = (1...9).map { number in
            let item = NSMenuItem(title: String(localized: "Space \(number)"), action: #selector(AppDelegate.selectSpace(_:)), keyEquivalent: "\(number)")
            item.keyEquivalentModifierMask = .control
            item.tag = number - 1
            return item
        }
        let item = submenu(title: String(localized: "Spaces"), items: customizable(items))
        item.submenu?.delegate = delegate
        return item
    }

    /// Their shortcut can be changed in the settings, which save it under the item's identifier.
    private static func customizable(_ items: [NSMenuItem]) -> [NSMenuItem] {
        for item in items {
            guard let action = item.action else { continue }
            let name = NSStringFromSelector(action).replacing(":", with: "")
            let id = action == #selector(AppDelegate.selectSpace(_:)) ? "\(name)\(item.tag + 1)" : name
            item.identifier = NSUserInterfaceItemIdentifier(Shortcuts.identifierPrefix + id)
        }
        return items
    }

    private static func submenu(title: String, items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        items.forEach(submenu.addItem)
        item.submenu = submenu
        return item
    }

    private static func optionCommand(_ item: NSMenuItem) -> NSMenuItem {
        item.keyEquivalentModifierMask = [.command, .option]
        return item
    }

    /// Arc's split view shortcuts.
    private static func controlShift(_ item: NSMenuItem) -> NSMenuItem {
        item.keyEquivalentModifierMask = [.control, .shift]
        return item
    }

    private static func shifted(_ item: NSMenuItem) -> NSMenuItem {
        item.keyEquivalentModifierMask = [.command, .shift]
        return item
    }
}
