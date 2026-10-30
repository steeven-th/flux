import AppKit

/// The line between a page and its DevTools, dragged to resize them. A window of its own, over
/// the two page windows.
@MainActor
final class DevToolsResizeHandle {
    private let window: NSWindow
    private let handle = SidebarResizeHandle()

    init(onDrag: @escaping (CGFloat) -> Void) {
        window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // Clear, but still taking the drag.
        window.ignoresMouseEvents = false
        handle.onDrag = onDrag
        window.contentView = handle
    }

    /// Added again each time, so it stays above page windows added since.
    func show(frame: NSRect, over host: NSWindow) {
        host.removeChildWindow(window)
        window.setFrame(frame, display: true)
        host.addChildWindow(window, ordered: .above)
    }

    func hide() {
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
    }
}
