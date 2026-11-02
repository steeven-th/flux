import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The browser windows, in the order they opened.
    private var windows: [MainWindowController] = []
    /// The one with the keyboard, or the last one that had it. Commands act on it.
    private weak var activeWindow: MainWindowController?
    private var windowController: MainWindowController? {
        activeWindow ?? windows.first
    }
    private var state: BrowserState? {
        windowController?.state
    }
    /// The active window's state, or a regular window's when it is private: links from other apps
    /// and new windows never go to a private window.
    private var regularState: BrowserState? {
        state.flatMap { $0.isPrivate ? nil : $0 } ?? windows.first { !$0.state.isPrivate }?.state
    }
    /// The first window's state set Flux's callbacks up, so it lives on after its window closes.
    private var firstState: BrowserState?
    private var dialogFixer: ChromiumDialogFixer?
    private var isRelaunching = false
    private var welcome: WelcomeWindowController?
    /// Links from other apps that came before the browser window, at the first launch.
    private var pendingLinks: [(url: URL, app: SourceApp?)] = []
    private let database: Result<AppDatabase, any Error>

    init(database: Result<AppDatabase, any Error>) {
        self.database = database
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = MainMenu.make(spacesMenuDelegate: self)
        NSApp.mainMenu = menu
        Shortcuts.install(in: menu, database: try? database.get())
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
        // Before Chromium opens the profiles.
        PendingHistory.applyAll()
        let state: BrowserState
        do {
            state = try BrowserState(appDatabase: database)
        } catch {
            showFatalError(error)
            return
        }
        FLXEngine.externalPageHandler = { [weak self] url, profilePath in
            self?.regularState?.openExternalPage(url, profilePath: profilePath)
        }
        prepare(state)
        state.onExtensionInstall = { [weak self] item, spaceID in
            guard let state = self?.state, !ExtensionInstaller.shared.didInstall(item.id, inSpace: spaceID) else { return }
            ExtensionInstaller.shared.ask(toInstall: item, state: state, justInstalled: true)
        }
        state.startArchiving()
        state.startSavingScrollPositions()
        state.startSleepingTabs()
        firstState = state
        let windowController = openWindow(state)
        if state.isWindowFullScreen { windowController.window?.toggleFullScreen(nil) }
        for saved in state.windowsToRestore {
            openWindow(BrowserState(sharing: state, showing: saved))
        }
        windowController.window?.makeKeyAndOrderFront(nil)
        activeWindow = windowController
        watchKeyWindow()
        let links = pendingLinks
        pendingLinks = []
        links.forEach { openFromOtherApp($0.url, from: $0.app) }
        if state.selectedTab == nil, links.isEmpty {
            windowController.showCommandBar(.newTab)
        }
    }

    /// Each window saves its size and place under a name of its own.
    @discardableResult
    private func openWindow(_ state: BrowserState) -> MainWindowController {
        let names = Set(windows.compactMap { $0.window?.frameAutosaveName })
        let name = (1...).lazy.map { $0 == 1 ? "MainWindow" : "MainWindow \($0)" }.first { !names.contains($0) }!
        let controller = MainWindowController(state: state, frameName: state.isPrivate ? nil : name)
        controller.onClose = { [weak self, weak controller] in
            self?.windows.removeAll { $0 === controller }
        }
        windows.append(controller)
        controller.showWindow(nil)
        return controller
    }

    /// Pages are child windows that take the keyboard, so the window they belong to is looked up.
    private func watchKeyWindow() {
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = NSApp.keyWindow else { return }
                let root = sequence(first: window, next: \.parent).reduce(window) { $1 }
                if let controller = self.windows.first(where: { $0.window === root }) {
                    self.activeWindow = controller
                }
            }
        }
    }

    @objc func newWindow(_ sender: Any?) {
        guard let state = regularState else { return }
        let controller = openWindow(BrowserState(sharing: state, showing: .init(spaceID: state.selectedSpaceID, selectedTabIDs: [:]), isNew: true))
        activeWindow = controller
        // Once the window has the keyboard, which it takes after showing.
        DispatchQueue.main.async { controller.showCommandBar(.newTab) }
    }

    @objc func newPrivateWindow(_ sender: Any?) {
        guard let state else { return }
        let controller = openWindow(BrowserState(privateSharing: state))
        activeWindow = controller
        DispatchQueue.main.async { controller.showCommandBar(.newTab) }
    }

    @objc func closeWindow(_ sender: Any?) {
        windowController?.window?.performClose(nil)
    }

    /// Links clicked in other apps, and HTML files opened with Flux.
    func application(_ application: NSApplication, open urls: [URL]) {
        let app = SourceApp.sendingCurrentEvent()
        guard state != nil else {
            pendingLinks += urls.map { ($0, app) }
            return
        }
        urls.forEach { openFromOtherApp($0, from: app) }
    }

    /// The first link rule that matches decides where the link opens, the Links settings otherwise.
    private func openFromOtherApp(_ url: URL, from app: SourceApp?) {
        guard let state = regularState else { return }
        if let app, app.bundleID != Bundle.main.bundleIdentifier { state.noteLinkSource(app) }
        let rule = state.linkRule(for: url, from: app)
        let spaceID = rule?.spaceID ?? state.selectedSpaceID
        if rule?.opensLittleWindow ?? state.outsideLinksOpenLittleWindow {
            LittleWindowController.show(url: url.absoluteString, inSpace: spaceID, state: state)
        } else {
            state.selectedSpaceID = spaceID
            state.newTab(url: url.absoluteString, in: spaceID)
            windows.first { $0.state === state }?.window?.makeKeyAndOrderFront(nil)
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
                source.prepare(AppPaths.profileFolder(named: record.profileFolder), from: first.profileFolder)
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
        // Settings and other windows of their own close like any window. Pages, the command bar
        // and overlays are child windows of the main window.
        if let window = NSApp.keyWindow, !sequence(first: window, next: \.parent).contains(where: { $0 is MainWindow }) {
            window.performClose(nil)
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

    /// The little window's when one has the keyboard, the selected tab's otherwise.
    private var finder: PageFinder? {
        LittleWindowController.key?.model.finder ?? state?.selectedTab?.finder
    }

    @objc func showFindBar(_ sender: Any?) {
        finder?.show()
    }

    @objc func findNext(_ sender: Any?) {
        finder?.next()
    }

    @objc func findPrevious(_ sender: Any?) {
        finder?.previous()
    }

    @objc func findSelection(_ sender: Any?) {
        finder?.findSelection()
    }

    // Not selectNextTab(_:): windows answer that one first, for their own tabs, and disable it.
    @objc func showNextTab(_ sender: Any?) {
        state?.selectTab(after: 1)
    }

    @objc func showPreviousTab(_ sender: Any?) {
        state?.selectTab(after: -1)
    }

    @objc func selectTabNumber(_ sender: NSMenuItem) {
        state?.selectTab(number: sender.tag)
    }

    @objc func duplicateTab(_ sender: Any?) {
        guard let state, let tab = state.selectedTab else { return }
        state.duplicate(tab)
    }

    /// The little window's page when one has the keyboard.
    @objc func copyAddress(_ sender: Any?) {
        guard let url = LittleWindowController.key?.model.url ?? state?.selectedTab?.url,
              let window = NSApp.keyWindow.map({ $0.parent ?? $0 }) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        Toast.show(String(localized: "Address Copied"), over: window)
    }

    @objc func toggleMute(_ sender: Any?) {
        state?.selectedTab?.toggleMute()
    }

    @objc func reopenClosedTab(_ sender: Any?) {
        state?.reopenClosedTab()
    }

    /// The little window's page when one has the keyboard, the selected tab's otherwise.
    private var shownPage: FLXBrowserView? {
        LittleWindowController.key?.model.page ?? state?.selectedTab?.browserView
    }

    @objc func stopLoading(_ sender: Any?) {
        shownPage?.stopLoading()
    }

    @objc func printPage(_ sender: Any?) {
        shownPage?.print()
    }

    @objc func savePage(_ sender: Any?) {
        shownPage?.savePage()
    }

    @objc func viewSource(_ sender: Any?) {
        guard let state, let page = shownPage, !page.currentURL.hasPrefix("view-source:") else { return }
        state.newTab(url: "view-source:" + page.currentURL)
    }

    @objc func toggleDevTools(_ sender: Any?) {
        guard let tab = state?.selectedTab else { return }
        if tab.devTools == nil {
            tab.browserView.showDevTools(onPanel: nil)
        } else {
            tab.browserView.closeDevTools()
        }
    }

    @objc func showConsole(_ sender: Any?) {
        state?.selectedTab?.show(.console)
    }

    @objc func inspectElement(_ sender: Any?) {
        state?.selectedTab?.show(.picker)
    }

    /// Pages and panels are child windows, often the ones with the keyboard, so the window they
    /// belong to is the one minimized or zoomed.
    private var frontWindow: NSWindow? {
        NSApp.keyWindow.map { window in sequence(first: window, next: \.parent).reduce(window) { $1 } }
    }

    @objc func minimizeWindow(_ sender: Any?) {
        frontWindow?.miniaturize(nil)
    }

    @objc func zoomWindow(_ sender: Any?) {
        frontWindow?.zoom(nil)
    }

    @objc func showShortcutSettings(_ sender: Any?) {
        guard let state else { return }
        SettingsWindowController.showShortcuts(state: state)
    }

    @objc func zoomIn(_ sender: Any?) {
        zoom(.in)
    }

    @objc func zoomOut(_ sender: Any?) {
        zoom(.out)
    }

    @objc func resetZoom(_ sender: Any?) {
        zoom(.reset)
    }

    /// Chromium zooms every page of the site in the profile, so other tabs are read again.
    private func zoom(_ zoom: FLXZoom) {
        if let little = LittleWindowController.key {
            little.model.page.zoom(zoom)
        } else {
            state?.selectedTab?.zoom(zoom)
        }
        state?.tabs.forEach { $0.refreshZoom() }
    }

    @objc func goBack(_ sender: Any?) {
        state?.selectedTab?.goBack()
    }

    @objc func goForward(_ sender: Any?) {
        state?.selectedTab?.goForward()
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
        if [#selector(showFindBar(_:)), #selector(findNext(_:)), #selector(findPrevious(_:)), #selector(findSelection(_:))].contains(menuItem.action) {
            return finder != nil
        }
        if menuItem.action == #selector(toggleMute(_:)) {
            menuItem.title = state?.selectedTab?.isMuted == true ? String(localized: "Unmute Tab") : String(localized: "Mute Tab")
            return state?.selectedTab != nil
        }
        if menuItem.action == #selector(reopenClosedTab(_:)) {
            return state?.archivedTabsInSelectedSpace.isEmpty == false
        }
        if [#selector(showNextTab(_:)), #selector(showPreviousTab(_:)), #selector(selectTabNumber(_:)), #selector(duplicateTab(_:))].contains(menuItem.action) {
            return state?.selectedTab != nil
        }
        if menuItem.action == #selector(copyAddress(_:)) {
            return LittleWindowController.key != nil || state?.selectedTab != nil
        }
        if [#selector(zoomIn(_:)), #selector(zoomOut(_:)), #selector(resetZoom(_:))].contains(menuItem.action) {
            return LittleWindowController.key != nil || state?.selectedTab != nil
        }
        // DevTools show next to a tab's page, not in little windows.
        if [#selector(toggleDevTools(_:)), #selector(showConsole(_:)), #selector(inspectElement(_:))].contains(menuItem.action) {
            if menuItem.action == #selector(toggleDevTools(_:)) {
                menuItem.title = state?.selectedTab?.devTools == nil ? String(localized: "Developer Tools") : String(localized: "Hide Developer Tools")
            }
            return LittleWindowController.key == nil && state?.selectedTab != nil
        }
        if [#selector(stopLoading(_:)), #selector(printPage(_:)), #selector(savePage(_:)), #selector(viewSource(_:))].contains(menuItem.action) {
            return LittleWindowController.key != nil || state?.selectedTab != nil
        }
        // Text fields of Flux's own take ⌘← and ⌘→ to move the caret.
        if [#selector(goBack(_:)), #selector(goForward(_:))].contains(menuItem.action),
           menuItem.tag == MainMenu.arrowNavigationTag, NSApp.keyWindow?.firstResponder is NSText {
            return false
        }
        if menuItem.action == #selector(goBack(_:)) {
            return state?.selectedTab?.canGoBack ?? false
        }
        if menuItem.action == #selector(goForward(_:)) {
            return state?.selectedTab?.canGoForward ?? false
        }
        if menuItem.action == #selector(togglePin(_:)) {
            guard let state, let tab = state.selectedTab else { return false }
            return tab.isPinned || state.canMove(.tab(tab), to: .pinned, parentID: nil)
        }
        return true
    }
}
