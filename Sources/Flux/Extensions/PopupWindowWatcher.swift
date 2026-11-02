import AppKit

/// Chrome hangs an extension's popup from its own toolbar, which Flux hides. The watcher notes the
/// windows on screen before the action runs, waits for the popup's window to appear, then keeps it
/// under the button that was clicked as the popup resizes to its content.
@MainActor
final class PopupWindowWatcher {
    /// Watchers following a popup stay alive until it closes.
    private static var following: [ObjectIdentifier: PopupWindowWatcher] = [:]

    private let windowsBefore: Set<ObjectIdentifier>
    private weak var anchor: NSView?
    private weak var popup: NSWindow?
    /// Where the popup's top left corner goes, under the button.
    private var popupTop = NSPoint.zero
    private var observers: [NSObjectProtocol] = []

    init(anchor: NSView) {
        self.anchor = anchor
        windowsBefore = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
    }

    /// The popup shows once its page has loaded. Actions without a popup never show one, so the
    /// watcher gives up after three seconds.
    func start(checksLeft: Int = 60) {
        if let popup = newPopupWindow() {
            follow(popup)
        } else if checksLeft > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                MainActor.assumeIsolated { self.start(checksLeft: checksLeft - 1) }
            }
        }
    }

    /// Chrome's popup is a borderless window. An extension opening a window of its own is titled.
    private func newPopupWindow() -> NSWindow? {
        NSApp.windows.first { window in
            !windowsBefore.contains(ObjectIdentifier(window)) && window.isVisible && window.frame.width > 1
                && !window.styleMask.contains(.titled) && !(window is NSPanel)
        }
    }

    private func follow(_ popup: NSWindow) {
        guard let anchor, let anchorWindow = anchor.window else { return }
        let button = anchorWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        self.popup = popup
        popupTop = NSPoint(x: button.minX, y: button.minY - 6)
        keepUnderButton()
        let id = ObjectIdentifier(popup)
        let center = NotificationCenter.default
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            observers.append(center.addObserver(forName: name, object: popup, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.keepUnderButton() }
            })
        }
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: popup, queue: .main) { _ in
            MainActor.assumeIsolated {
                guard let watcher = Self.following.removeValue(forKey: id) else { return }
                watcher.observers.forEach(center.removeObserver)
                watcher.observers = []
            }
        })
        Self.following[id] = self
    }

    private func keepUnderButton() {
        guard let popup else { return }
        let origin = NSPoint(x: popupTop.x, y: popupTop.y - popup.frame.height)
        if popup.frame.origin != origin { popup.setFrameOrigin(origin) }
    }
}
