import AppKit

@MainActor
enum MainMenu {
    /// `spacesMenuDelegate` fills in the spaces' names each time the Spaces menu opens.
    static func make(spacesMenuDelegate: NSMenuDelegate) -> NSMenu {
        let menu = NSMenu()
        let services = NSMenu(title: String(localized: "Services"))
        NSApp.servicesMenu = services
        let servicesItem = NSMenuItem(title: String(localized: "Services"), action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        menu.addItem(submenu(title: String(localized: "Flux"), items: [
            NSMenuItem(title: String(localized: "About Flux"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""),
            .separator(),
        ] + customizable([
            NSMenuItem(title: String(localized: "Settings…"), action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ","),
            .separator(),
            shifted(NSMenuItem(title: String(localized: "Extensions…"), action: #selector(AppDelegate.showExtensions(_:)), keyEquivalent: "e")),
            NSMenuItem(title: String(localized: "Passwords…"), action: #selector(AppDelegate.showPasswords(_:)), keyEquivalent: ""),
        ]) + [
            .separator(),
            servicesItem,
            .separator(),
            NSMenuItem(title: String(localized: "Hide Flux"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"),
            optionCommand(NSMenuItem(title: String(localized: "Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")),
            NSMenuItem(title: String(localized: "Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""),
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
            shifted(NSMenuItem(title: String(localized: "Save Page As…"), action: #selector(AppDelegate.savePage(_:)), keyEquivalent: "s")),
            NSMenuItem(title: String(localized: "Print…"), action: #selector(AppDelegate.printPage(_:)), keyEquivalent: "p"),
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
            // Chromium's pages answer pasteAndMatchStyle:, as in Chrome.
            optionShiftCommand(NSMenuItem(title: String(localized: "Paste and Match Style"), action: Selector(("pasteAndMatchStyle:")), keyEquivalent: "v")),
            NSMenuItem(title: String(localized: "Delete"), action: #selector(NSText.delete(_:)), keyEquivalent: ""),
            NSMenuItem(title: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
            .separator(),
        ] + customizable([
            NSMenuItem(title: String(localized: "Find…"), action: #selector(AppDelegate.showFindBar(_:)), keyEquivalent: "f"),
            NSMenuItem(title: String(localized: "Find Next"), action: #selector(AppDelegate.findNext(_:)), keyEquivalent: "g"),
            shifted(NSMenuItem(title: String(localized: "Find Previous"), action: #selector(AppDelegate.findPrevious(_:)), keyEquivalent: "g")),
            NSMenuItem(title: String(localized: "Use Selection for Find"), action: #selector(AppDelegate.findSelection(_:)), keyEquivalent: "e"),
        ])))
        menu.addItem(submenu(title: String(localized: "View"), items: customizable([
            NSMenuItem(title: String(localized: "Toggle Sidebar"), action: #selector(AppDelegate.showOrHideSidebar(_:)), keyEquivalent: "s"),
            .separator(),
            controlShift(NSMenuItem(title: String(localized: "Add Split View"), action: #selector(AppDelegate.addSplitPane(_:)), keyEquivalent: "=")),
            controlShift(NSMenuItem(title: String(localized: "Close Split Pane"), action: #selector(AppDelegate.closeSplitPane(_:)), keyEquivalent: "-")),
            .separator(),
            NSMenuItem(title: String(localized: "Reload Page"), action: #selector(AppDelegate.reloadPage(_:)), keyEquivalent: "r"),
            shifted(NSMenuItem(title: String(localized: "Reload Ignoring Cache"), action: #selector(AppDelegate.reloadPageIgnoringCache(_:)), keyEquivalent: "r")),
            NSMenuItem(title: String(localized: "Stop Loading"), action: #selector(AppDelegate.stopLoading(_:)), keyEquivalent: "."),
            NSMenuItem(title: String(localized: "Back"), action: #selector(AppDelegate.goBack(_:)), keyEquivalent: "["),
            NSMenuItem(title: String(localized: "Forward"), action: #selector(AppDelegate.goForward(_:)), keyEquivalent: "]"),
            .separator(),
            NSMenuItem(title: String(localized: "Zoom In"), action: #selector(AppDelegate.zoomIn(_:)), keyEquivalent: "="),
            NSMenuItem(title: String(localized: "Zoom Out"), action: #selector(AppDelegate.zoomOut(_:)), keyEquivalent: "-"),
            NSMenuItem(title: String(localized: "Actual Size"), action: #selector(AppDelegate.resetZoom(_:)), keyEquivalent: "0"),
            .separator(),
            optionCommand(NSMenuItem(title: String(localized: "View Page Source"), action: #selector(AppDelegate.viewSource(_:)), keyEquivalent: "u")),
            optionCommand(NSMenuItem(title: String(localized: "Developer Tools"), action: #selector(AppDelegate.toggleDevTools(_:)), keyEquivalent: "i")),
            optionCommand(NSMenuItem(title: String(localized: "JavaScript Console"), action: #selector(AppDelegate.showConsole(_:)), keyEquivalent: "j")),
            optionCommand(NSMenuItem(title: String(localized: "Inspect Element"), action: #selector(AppDelegate.inspectElement(_:)), keyEquivalent: "c")),
        ]) + arrowNavigationItems()))
        menu.addItem(submenu(title: String(localized: "Tab"), items: customizable([
            control(NSMenuItem(title: String(localized: "Select Next Tab"), action: #selector(AppDelegate.showNextTab(_:)), keyEquivalent: "\t")),
            controlShift(NSMenuItem(title: String(localized: "Select Previous Tab"), action: #selector(AppDelegate.showPreviousTab(_:)), keyEquivalent: "\t")),
            .separator(),
            NSMenuItem(title: String(localized: "Duplicate Tab"), action: #selector(AppDelegate.duplicateTab(_:)), keyEquivalent: ""),
            shifted(NSMenuItem(title: String(localized: "Copy Address"), action: #selector(AppDelegate.copyAddress(_:)), keyEquivalent: "c")),
            NSMenuItem(title: String(localized: "Mute Tab"), action: #selector(AppDelegate.toggleMute(_:)), keyEquivalent: ""),
            .separator(),
            shifted(NSMenuItem(title: String(localized: "Reopen Closed Tab"), action: #selector(AppDelegate.reopenClosedTab(_:)), keyEquivalent: "t")),
        ] + tabNumberItems())))
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
        // AppKit lists the windows in the Window menu, and adds a search of the menus to Help.
        let window = submenu(title: String(localized: "Window"), items: [
            NSMenuItem(title: String(localized: "Minimize"), action: #selector(AppDelegate.minimizeWindow(_:)), keyEquivalent: "m"),
            NSMenuItem(title: String(localized: "Zoom"), action: #selector(AppDelegate.zoomWindow(_:)), keyEquivalent: ""),
            .separator(),
            NSMenuItem(title: String(localized: "Bring All to Front"), action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""),
        ])
        NSApp.windowsMenu = window.submenu
        menu.addItem(window)
        let help = submenu(title: String(localized: "Help"), items: [
            NSMenuItem(title: String(localized: "Keyboard Shortcuts"), action: #selector(AppDelegate.showShortcutSettings(_:)), keyEquivalent: ""),
        ])
        NSApp.helpMenu = help.submenu
        menu.addItem(help)
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
            let id = switch action {
            case #selector(AppDelegate.selectSpace(_:)): "\(name)\(item.tag + 1)"
            case #selector(AppDelegate.selectTabNumber(_:)): "\(name)\(item.tag)"
            default: name
            }
            item.identifier = NSUserInterfaceItemIdentifier(Shortcuts.identifierPrefix + id)
        }
        return items
    }

    /// ⌘← and ⌘→ go back and forward too, as in Chrome, out of text fields. Hidden, and fixed, since
    /// Back and Forward already have their own shortcuts.
    private static func arrowNavigationItems() -> [NSMenuItem] {
        [
            (String(localized: "Back"), #selector(AppDelegate.goBack(_:)), NSLeftArrowFunctionKey),
            (String(localized: "Forward"), #selector(AppDelegate.goForward(_:)), NSRightArrowFunctionKey),
        ].map { title, action, key in
            let item = NSMenuItem(title: title, action: action, keyEquivalent: String(UnicodeScalar(UInt16(key))!))
            item.tag = arrowNavigationTag
            item.isHidden = true
            item.allowsKeyEquivalentWhenHidden = true
            return item
        }
    }

    static let arrowNavigationTag = 1

    /// ⌘1 to ⌘8 select the first tabs and ⌘9 the last. Hidden, as in other browsers, but their
    /// shortcuts work.
    private static func tabNumberItems() -> [NSMenuItem] {
        (1...9).map { number in
            let title = number == 9 ? String(localized: "Select Last Tab") : String(localized: "Select Tab \(number)")
            let item = NSMenuItem(title: title, action: #selector(AppDelegate.selectTabNumber(_:)), keyEquivalent: "\(number)")
            item.tag = number
            item.isHidden = true
            item.allowsKeyEquivalentWhenHidden = true
            return item
        }
    }

    private static func submenu(title: String, items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        items.forEach(submenu.addItem)
        item.submenu = submenu
        return item
    }

    private static func optionShiftCommand(_ item: NSMenuItem) -> NSMenuItem {
        item.keyEquivalentModifierMask = [.command, .option, .shift]
        return item
    }

    private static func optionCommand(_ item: NSMenuItem) -> NSMenuItem {
        item.keyEquivalentModifierMask = [.command, .option]
        return item
    }

    private static func control(_ item: NSMenuItem) -> NSMenuItem {
        item.keyEquivalentModifierMask = .control
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
