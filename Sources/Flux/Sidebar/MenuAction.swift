import AppKit

/// Menu items that run a closure. The item keeps the closure's target alive.
@MainActor
final class MenuAction: NSObject {
    private let handler: () -> Void

    private init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    static func item(_ title: String, _ handler: @escaping () -> Void) -> NSMenuItem {
        let target = MenuAction(handler)
        let item = NSMenuItem(title: title, action: #selector(run), keyEquivalent: "")
        item.target = target
        item.representedObject = target
        return item
    }

    @objc private func run() {
        handler()
    }
}
