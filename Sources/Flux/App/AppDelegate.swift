import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: BrowserState?
    private var windowController: MainWindowController?
    private var dialogFixer: ChromiumDialogFixer?
    private let database: Result<AppDatabase, any Error>

    init(database: Result<AppDatabase, any Error>) {
        self.database = database
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make(spacesMenuDelegate: self)
        dialogFixer = ChromiumDialogFixer()

        let state: BrowserState
        do {
            state = try BrowserState(appDatabase: database.get())
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Flux couldn't open its data"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        FLXEngine.externalPageHandler = { [weak state] url, profilePath in
            state?.openExternalPage(url, profilePath: profilePath)
        }
        let windowController = MainWindowController(state: state)
        windowController.showWindow(nil)
        self.state = state
        self.windowController = windowController
        if state.selectedTab == nil {
            windowController.showCommandBar(.newTab)
        }

        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc func newTab(_ sender: Any?) {
        windowController?.showCommandBar(.newTab)
    }

    @objc func openLocation(_ sender: Any?) {
        windowController?.showCommandBar(.selectedTab)
    }

    @objc func closeTab(_ sender: Any?) {
        guard let state, let tab = state.selectedTab else { return }
        state.close(tab)
    }

    @objc func togglePin(_ sender: Any?) {
        guard let state, let tab = state.selectedTab else { return }
        state.togglePin(tab)
    }

    @objc func newFolder(_ sender: Any?) {
        state?.createFolder()
    }

    @objc func selectSpace(_ sender: NSMenuItem) {
        state?.selectSpace(at: sender.tag)
    }

    @objc func openInChromeWindow(_ sender: Any?) {
        state?.openSelectedTabInChromeWindow()
    }

    @objc func showExtensions(_ sender: Any?) {
        state?.showExtensionsOfSelectedSpace()
    }

    @objc func showPasswords(_ sender: Any?) {
        state?.showPasswordsOfSelectedSpace()
    }

    @objc func reloadPage(_ sender: Any?) {
        state?.selectedTab?.browserView.reload()
    }

    @objc func goBack(_ sender: Any?) {
        state?.selectedTab?.browserView.goBack()
    }

    @objc func goForward(_ sender: Any?) {
        state?.selectedTab?.browserView.goForward()
    }
}

extension AppDelegate: NSMenuDelegate, NSMenuItemValidation {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let spaces = state?.spaces else { return }
        for item in menu.items where item.action == #selector(selectSpace(_:)) {
            item.title = spaces.indices.contains(item.tag) ? spaces[item.tag].name : "Space \(item.tag + 1)"
            item.isHidden = !spaces.indices.contains(item.tag)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(selectSpace(_:)) {
            return state?.spaces.indices.contains(menuItem.tag) ?? false
        }
        return true
    }
}
