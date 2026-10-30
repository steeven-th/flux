import AppKit
import SwiftUI

/// Flux's settings, one pane per toolbar item like the system's own apps.
@MainActor
final class SettingsWindowController: NSWindowController {
    private static var shared: SettingsWindowController?

    private let tabs = NSTabViewController()

    static func show(state: BrowserState) {
        let controller = shared ?? SettingsWindowController(state: state)
        shared = controller
        controller.showWindow(nil)
        NSApp.activate()
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
        tabs.addTabViewItem(Self.item("Developer", symbol: "hammer", DeveloperSettings(state: state)))
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
        let item = NSTabViewItem(viewController: controller)
        item.label = String(localized: label)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: item.label)
        return item
    }
}
