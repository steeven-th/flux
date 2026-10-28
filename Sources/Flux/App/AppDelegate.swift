import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: BrowserState?
    private var windowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()

        let state = BrowserState(spaces: Space.defaults)
        let windowController = MainWindowController(state: state)
        windowController.showWindow(nil)
        self.state = state
        self.windowController = windowController

        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc func newTab(_ sender: Any?) {
        state?.newTab()
    }

    @objc func closeTab(_ sender: Any?) {
        guard let state, let tab = state.selectedTab else { return }
        state.close(tab)
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
