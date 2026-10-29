import AppKit

@MainActor
enum MainMenu {
    /// `spacesMenuDelegate` fills in the spaces' names each time the Spaces menu opens.
    static func make(spacesMenuDelegate: NSMenuDelegate) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu(title: String(localized: "Flux"), items: [
            NSMenuItem(title: String(localized: "Settings…"), action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ","),
            .separator(),
            shifted(NSMenuItem(title: String(localized: "Extensions…"), action: #selector(AppDelegate.showExtensions(_:)), keyEquivalent: "e")),
            NSMenuItem(title: String(localized: "Passwords…"), action: #selector(AppDelegate.showPasswords(_:)), keyEquivalent: ""),
            .separator(),
            NSMenuItem(title: String(localized: "Quit Flux"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]))
        menu.addItem(submenu(title: String(localized: "File"), items: [
            NSMenuItem(title: String(localized: "New Tab"), action: #selector(AppDelegate.newTab(_:)), keyEquivalent: "t"),
            NSMenuItem(title: String(localized: "Open Location…"), action: #selector(AppDelegate.openLocation(_:)), keyEquivalent: "l"),
            NSMenuItem(title: String(localized: "Close Tab"), action: #selector(AppDelegate.closeTab(_:)), keyEquivalent: "w"),
            NSMenuItem(title: String(localized: "Pin or Unpin Tab"), action: #selector(AppDelegate.togglePin(_:)), keyEquivalent: "d"),
            NSMenuItem(title: String(localized: "New Folder"), action: #selector(AppDelegate.newFolder(_:)), keyEquivalent: ""),
        ]))
        menu.addItem(submenu(title: String(localized: "Edit"), items: [
            NSMenuItem(title: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z"),
            shifted(NSMenuItem(title: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "z")),
            .separator(),
            NSMenuItem(title: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ]))
        menu.addItem(submenu(title: String(localized: "View"), items: [
            NSMenuItem(title: String(localized: "Toggle Sidebar"), action: #selector(AppDelegate.showOrHideSidebar(_:)), keyEquivalent: "s"),
            .separator(),
            NSMenuItem(title: String(localized: "Reload Page"), action: #selector(AppDelegate.reloadPage(_:)), keyEquivalent: "r"),
            NSMenuItem(title: String(localized: "Back"), action: #selector(AppDelegate.goBack(_:)), keyEquivalent: "["),
            NSMenuItem(title: String(localized: "Forward"), action: #selector(AppDelegate.goForward(_:)), keyEquivalent: "]"),
        ]))
        menu.addItem(submenu(title: String(localized: "History"), items: [
            NSMenuItem(title: String(localized: "Show All History"), action: #selector(AppDelegate.showHistory(_:)), keyEquivalent: "y"),
            shifted(NSMenuItem(
                title: String(localized: "Clear Browsing Data…"), action: #selector(AppDelegate.clearBrowsingData(_:)), keyEquivalent: "\u{8}"
            )),
        ]))
        menu.addItem(spacesMenu(delegate: spacesMenuDelegate))
        menu.addItem(submenu(title: String(localized: "Debug"), items: [
            NSMenuItem(title: String(localized: "Open Tab in Chrome Window"), action: #selector(AppDelegate.openInChromeWindow(_:)), keyEquivalent: ""),
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
        let item = submenu(title: String(localized: "Spaces"), items: items)
        item.submenu?.delegate = delegate
        return item
    }

    private static func submenu(title: String, items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        items.forEach(submenu.addItem)
        item.submenu = submenu
        return item
    }

    private static func shifted(_ item: NSMenuItem) -> NSMenuItem {
        item.keyEquivalentModifierMask = [.command, .shift]
        return item
    }
}
