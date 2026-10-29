import AppKit

@MainActor
enum MainMenu {
    /// `spacesMenuDelegate` fills in the spaces' names each time the Spaces menu opens.
    static func make(spacesMenuDelegate: NSMenuDelegate) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu(title: "Flux", items: [
            shifted(NSMenuItem(title: "Extensions…", action: #selector(AppDelegate.showExtensions(_:)), keyEquivalent: "e")),
            .separator(),
            NSMenuItem(title: "Quit Flux", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]))
        menu.addItem(submenu(title: "File", items: [
            NSMenuItem(title: "New Tab", action: #selector(AppDelegate.newTab(_:)), keyEquivalent: "t"),
            NSMenuItem(title: "Open Location…", action: #selector(AppDelegate.openLocation(_:)), keyEquivalent: "l"),
            NSMenuItem(title: "Close Tab", action: #selector(AppDelegate.closeTab(_:)), keyEquivalent: "w"),
            NSMenuItem(title: "Pin or Unpin Tab", action: #selector(AppDelegate.togglePin(_:)), keyEquivalent: "d"),
            NSMenuItem(title: "New Folder", action: #selector(AppDelegate.newFolder(_:)), keyEquivalent: ""),
        ]))
        menu.addItem(submenu(title: "Edit", items: [
            NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"),
            shifted(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")),
            .separator(),
            NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ]))
        menu.addItem(submenu(title: "View", items: [
            NSMenuItem(title: "Reload Page", action: #selector(AppDelegate.reloadPage(_:)), keyEquivalent: "r"),
            NSMenuItem(title: "Back", action: #selector(AppDelegate.goBack(_:)), keyEquivalent: "["),
            NSMenuItem(title: "Forward", action: #selector(AppDelegate.goForward(_:)), keyEquivalent: "]"),
        ]))
        menu.addItem(spacesMenu(delegate: spacesMenuDelegate))
        menu.addItem(submenu(title: "Debug", items: [
            NSMenuItem(title: "Open Tab in Chrome Window", action: #selector(AppDelegate.openInChromeWindow(_:)), keyEquivalent: ""),
        ]))
        return menu
    }

    /// ⌃1 to ⌃9 select the first nine spaces. The items exist up front so the shortcuts work
    /// without opening the menu.
    private static func spacesMenu(delegate: NSMenuDelegate) -> NSMenuItem {
        let items = (1...9).map { number in
            let item = NSMenuItem(title: "Space \(number)", action: #selector(AppDelegate.selectSpace(_:)), keyEquivalent: "\(number)")
            item.keyEquivalentModifierMask = .control
            item.tag = number - 1
            return item
        }
        let item = submenu(title: "Spaces", items: items)
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
