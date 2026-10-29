import AppKit

/// Lets the user drag a rectangle over a page, for a capture of that area. Escape or a click
/// without dragging cancels.
@MainActor
final class AreaSelector: NSWindow {
    private static var current: AreaSelector?

    private let onSelect: (CGRect?) -> Void

    /// The rectangle is in the page view's points, from its top left corner.
    static func select(over page: FLXBrowserView, onSelect: @escaping (CGRect?) -> Void) {
        guard let host = page.window else { return onSelect(nil) }
        current?.finish(with: nil)
        let frame = host.convertToScreen(page.convert(page.bounds, to: nil))
        let selector = AreaSelector(frame: frame, onSelect: onSelect)
        host.addChildWindow(selector, ordered: .above)
        selector.makeKeyAndOrderFront(nil)
        current = selector
    }

    private init(frame: NSRect, onSelect: @escaping (CGRect?) -> Void) {
        self.onSelect = onSelect
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        let view = SelectionView()
        view.onFinish = { [weak self] rect in self?.finish(with: rect) }
        contentView = view
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        finish(with: nil)
    }

    private func finish(with rect: CGRect?) {
        parent?.removeChildWindow(self)
        orderOut(nil)
        Self.current = nil
        guard let rect, let content = contentView else { return onSelect(nil) }
        // AppKit counts from the bottom, the page from the top.
        onSelect(CGRect(x: rect.minX, y: content.bounds.height - rect.maxY, width: rect.width, height: rect.height))
    }
}

private final class SelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private var start: NSPoint?
    private var selection: NSRect?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = NSRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let selection, selection.width > 4, selection.height > 4 else { return onFinish?(nil) ?? () }
        onFinish?(selection)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        let dim = NSBezierPath(rect: bounds)
        if let selection {
            dim.append(NSBezierPath(rect: selection))
            dim.windingRule = .evenOdd
        }
        dim.fill()
        if let selection {
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
        }
    }
}
