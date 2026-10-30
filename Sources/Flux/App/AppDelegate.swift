import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: BrowserState?
    private var windowController: MainWindowController?
    private var dialogFixer: ChromiumDialogFixer?
    private var isRelaunching = false
    private var welcome: WelcomeWindowController?
    /// Links from other apps that came before the browser window, at the first launch.
    private var pendingURLs: [URL] = []
    private let database: Result<AppDatabase, any Error>

    init(database: Result<AppDatabase, any Error>) {
        self.database = database
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make(spacesMenuDelegate: self)
        dialogFixer = ChromiumDialogFixer()

        let database: AppDatabase
        do {
            database = try self.database.get()
        } catch {
            showFatalError(error)
            return
        }
        if (try? database.spaces().isEmpty) == true {
            showWelcome { [weak self] choices in self?.finishWelcome(choices, database: database) }
        } else {
            startBrowsing(database: database)
        }
        NSApp.activate()
    }

    /// `prepare` runs before the window shows, once the spaces are open.
    private func startBrowsing(database: AppDatabase, prepare: (BrowserState) -> Void = { _ in }) {
        let state: BrowserState
        do {
            state = try BrowserState(appDatabase: database)
        } catch {
            showFatalError(error)
            return
        }
        FLXEngine.externalPageHandler = { [weak state] url, profilePath in
            state?.openExternalPage(url, profilePath: profilePath)
        }
        prepare(state)
        state.startArchiving()
        state.startSavingScrollPositions()
        let windowController = MainWindowController(state: state)
        windowController.showWindow(nil)
        if state.isWindowFullScreen { windowController.window?.toggleFullScreen(nil) }
        self.state = state
        self.windowController = windowController
        watchSplitShortcuts()
        let urls = pendingURLs
        pendingURLs = []
        urls.forEach(openFromOtherApp)
        if state.selectedTab == nil, urls.isEmpty {
            windowController.showCommandBar(.newTab)
        }
    }

    /// Links clicked in other apps, and HTML files opened with Flux.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard state != nil else {
            pendingURLs += urls
            return
        }
        urls.forEach(openFromOtherApp)
    }

    private func openFromOtherApp(_ url: URL) {
        guard let state else { return }
        if state.outsideLinksOpenLittleWindow {
            LittleWindowController.show(url: url.absoluteString, state: state)
        } else {
            state.newTab(url: url.absoluteString)
            windowController?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
    }

    private func showWelcome(onFinish: @escaping (WelcomeModel) -> Void) {
        let welcome = WelcomeWindowController(onFinish: onFinish)
        welcome.showWindow(nil)
        self.welcome = welcome
    }

    private func finishWelcome(_ choices: WelcomeModel, database: AppDatabase) {
        // The other browser's first space becomes the first space, and its other spaces come after it.
        let source = choices.importSource
        let imported = choices.importedSpaces
        do {
            if let source, let first = imported.first {
                let record = try BrowserState.createFirstSpace(
                    name: first.name, icon: first.icon, color: first.color ?? BrowserState.spaceColors[0], in: database
                )
                if source.canTransferProfiles {
                    ProfileTransfer.transfer(
                        from: first.profileFolder, to: AppPaths.profileFolder(named: record.profileFolder), keys: ProfileTransfer.keys(for: source)
                    )
                }
            } else {
                let name = choices.name.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = try BrowserState.createFirstSpace(
                    name: name, icon: choices.icon.isEmpty ? nil : choices.icon, color: choices.color, in: database
                )
            }
        } catch {
            showFatalError(error)
            return
        }
        startBrowsing(database: database) { state in
            if let source, let first = imported.first {
                state.importSpaces(imported, from: source, destinations: [first.id: state.selectedSpace.id], includesToday: choices.importsToday)
            }
            for profile in state.profilesInUse {
                state.setSearchEngine(choices.searchEngine, forProfile: profile.folder)
            }
            if let manager = choices.passwordManager {
                for profile in state.profilesInUse {
                    state.passwordManager(forProfile: profile.folder)?.setEnabled(false)
                }
                state.newTab(url: manager.storeURL)
            }
        }
        // After the main window shows, or closing the last window would quit Flux.
        welcome?.close()
        welcome = nil
    }

    private func showFatalError(_ error: any Error) {
        let alert = NSAlert(error: error)
        alert.messageText = String(localized: "Flux couldn't open its data")
        alert.runModal()
        NSApp.terminate(nil)
    }

    /// Shows the welcome window again without creating anything, to check how it looks.
    @objc func previewWelcome(_ sender: Any?) {
        showWelcome { [weak self] _ in
            self?.welcome?.close()
            self?.welcome = nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let state, state.warnsBeforeQuitting, !isRelaunching else { return .terminateNow }
        return confirmQuit(state) ? .terminateNow : .terminateCancel
    }

    private func confirmQuit(_ state: BrowserState) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Quit Flux?")
        alert.addButton(withTitle: String(localized: "Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "Don't ask again")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        if alert.suppressionButton?.state == .on { state.warnsBeforeQuitting = false }
        return true
    }

    func applicationDidResignActive(_ notification: Notification) {
        state?.selectedTab?.saveScrollPosition()
    }

    /// Quits, then opens Flux again once this process has exited: Chromium keeps its profiles
    /// locked until then.
    func relaunch() {
        let script = "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; open \"$0\""
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", script, Bundle.main.bundlePath]
        try? process.run()
        isRelaunching = true
        NSApp.terminate(nil)
    }

    @objc func showSettings(_ sender: Any?) {
        guard let state else { return }
        SettingsWindowController.show(state: state)
    }

    @objc func newTab(_ sender: Any?) {
        windowController?.showCommandBar(.newTab)
    }

    @objc func openLocation(_ sender: Any?) {
        windowController?.showCommandBar(.selectedTab)
    }

    @objc func closeTab(_ sender: Any?) {
        if let little = LittleWindowController.key {
            little.close()
            return
        }
        if state?.peek != nil {
            state?.closePeek()
            return
        }
        guard let state, let tab = state.selectedTab else { return }
        state.close(tab)
    }

    @objc func importFromBrowser(_ sender: Any?) {
        guard let state else { return }
        ImportWindowController.show(state: state)
    }

    @objc func addSplitPane(_ sender: Any?) {
        showSplitPaneCommandBar(after: true)
    }

    func showSplitPaneCommandBar(after: Bool) {
        windowController?.showCommandBar(.splitPane(after: after))
    }

    @objc func closeSplitPane(_ sender: Any?) {
        guard let state, state.selectedSplit != nil, let tab = state.selectedTab else { return }
        state.closePane(tab)
    }

    /// ⌃⇧= and ⌃⇧−, read from the key itself: what Shift makes of it depends on the keyboard,
    /// "+" or "_" on some, "+" or "6" on a French one, so the menu can't match it.
    private func watchSplitShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.control, .shift],
                  let key = event.characters(byApplyingModifiers: []) else { return event }
            switch key {
            case "=":
                if self?.state?.canAddSplitPane == true { self?.addSplitPane(nil) }
            case "-":
                self?.closeSplitPane(nil)
            default:
                return event
            }
            return nil
        }
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

    @objc func showHistory(_ sender: Any?) {
        state?.showHistoryOfSelectedSpace()
    }

    @objc func openLittleWindowInSpace(_ sender: Any?) {
        LittleWindowController.key?.moveToSpace()
    }

    @objc func showLibrary(_ sender: Any?) {
        state?.isLibraryShown = true
    }

    @objc func showArchive(_ sender: Any?) {
        state?.isArchiveShown = true
    }

    @objc func clearBrowsingData(_ sender: Any?) {
        state?.showClearBrowsingDataOfSelectedSpace()
    }

    // Not toggleSidebar(_:): SwiftUI's hosting views answer that one first, for their own sidebars,
    // and disable it.
    @objc func showOrHideSidebar(_ sender: Any?) {
        windowController?.toggleSidebar()
    }

    @objc func reloadPage(_ sender: Any?) {
        state?.selectedTab?.browserView.reload()
    }

    @objc func reloadPageIgnoringCache(_ sender: Any?) {
        state?.selectedTab?.browserView.reloadIgnoringCache()
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
            item.title = spaces.indices.contains(item.tag) ? spaces[item.tag].name : String(localized: "Space \(item.tag + 1)")
            item.isHidden = !spaces.indices.contains(item.tag)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(openLittleWindowInSpace(_:)) {
            return LittleWindowController.key != nil
        }
        if menuItem.action == #selector(selectSpace(_:)) {
            return state?.spaces.indices.contains(menuItem.tag) ?? false
        }
        if menuItem.action == #selector(addSplitPane(_:)) {
            return state?.canAddSplitPane ?? false
        }
        if menuItem.action == #selector(closeSplitPane(_:)) {
            return state?.selectedSplit != nil
        }
        if menuItem.action == #selector(togglePin(_:)) {
            guard let state, let tab = state.selectedTab else { return false }
            return tab.isPinned || state.canMove(.tab(tab), to: .pinned, parentID: nil)
        }
        return true
    }
}
