import AppKit
import SwiftUI

/// Flux's settings, one pane per toolbar item like the system's own apps.
@MainActor
final class SettingsWindowController: NSWindowController {
    private static var shared: SettingsWindowController?

    private let tabs = NSTabViewController()
    private let developerSection = DeveloperSettings.Model()

    static func show(state: BrowserState) {
        let controller = shared ?? SettingsWindowController(state: state)
        shared = controller
        controller.showWindow(nil)
        NSApp.activate()
    }

    static func showShortcuts(state: BrowserState) {
        show(state: state)
        guard let controller = shared,
              let index = controller.tabs.tabViewItems.firstIndex(where: { $0.viewController is NSHostingController<ShortcutSettings> }) else { return }
        controller.tabs.selectedTabViewItemIndex = index
    }

    /// The developer pane, on the devices the responsive mode offers.
    static func showDevices(state: BrowserState) {
        show(state: state)
        guard let controller = shared else { return }
        controller.developerSection.section = .devices
        controller.tabs.selectedTabViewItemIndex = controller.tabs.tabViewItems.count - 1
        // Selecting a pane in code doesn't retitle the window the way a click does.
        controller.window?.title = controller.tabs.tabViewItems.last?.label ?? ""
    }

    private init(state: BrowserState) {
        tabs.tabStyle = .toolbar
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)

        tabs.addTabViewItem(Self.item("General", symbol: "gearshape", GeneralSettings(state: state) { [weak self] in
            self?.tabs.selectedTabViewItemIndex = 1
        }))
        tabs.addTabViewItem(Self.item("Profiles", symbol: "person.crop.circle", ProfileSettings(state: state)))
        tabs.addTabViewItem(Self.item("Links", symbol: "rectangle.on.rectangle", LinkSettings(state: state)))
        if let shortcuts = Shortcuts.shared {
            tabs.addTabViewItem(Self.item("Shortcuts", symbol: "command", ShortcutSettings(shortcuts: shortcuts)))
        }
        tabs.addTabViewItem(Self.item("Developer", symbol: "hammer", DeveloperSettings(state: state, model: developerSection)))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not available")
    }

    private static func item(_ label: LocalizedStringResource, symbol: String, _ view: some View) -> NSTabViewItem {
        let controller = NSHostingController(rootView: view)
        // The window takes each pane's size when it is selected.
        controller.sizingOptions = .preferredContentSize
        // The tab view controller titles the window after the selected pane.
        controller.title = String(localized: label)
        let item = NSTabViewItem(viewController: controller)
        item.label = String(localized: label)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: item.label)
        return item
    }
}
