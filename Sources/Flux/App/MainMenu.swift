import AppKit

enum MainMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu(title: "Flux", items: [
            shifted(NSMenuItem(title: "Extensions…", action: #selector(AppDelegate.showExtensions(_:)), keyEquivalent: "e")),
            .separator(),
            NSMenuItem(title: "Quit Flux", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]))
        menu.addItem(submenu(title: "File", items: [
            NSMenuItem(title: "New Tab", action: #selector(AppDelegate.newTab(_:)), keyEquivalent: "t"),
            NSMenuItem(title: "Close Tab", action: #selector(AppDelegate.closeTab(_:)), keyEquivalent: "w"),
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
        return menu
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
