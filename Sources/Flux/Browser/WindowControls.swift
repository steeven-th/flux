import AppKit

/// Close, minimize and full screen buttons acting on another window. The standard buttons only
/// show their colors and symbols in the window they belong to, while it is the main one.
final class WindowControls: NSView {
    static let size = NSSize(width: 52, height: 12)

    private let buttons: [WindowControlButton]

    init(for window: NSWindow) {
        buttons = [
            WindowControlButton(kind: .close) { [weak window] in window?.performClose(nil) },
            WindowControlButton(kind: .minimize) { [weak window] in window?.performMiniaturize(nil) },
            WindowControlButton(kind: .fullScreen(window)) { [weak window] in window?.toggleFullScreen(nil) },
        ]
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: CGFloat(index) * 20, y: 0, width: 12, height: 12)
            addSubview(button)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not available")
    }

    // Like the standard buttons, all three show their symbol while the pointer is on any of them.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        buttons.forEach { $0.showsSymbol = true }
    }

    override func mouseExited(with event: NSEvent) {
        buttons.forEach { $0.showsSymbol = false }
    }
}

private final class WindowControlButton: NSView {
    enum Kind {
        case close, minimize
        case fullScreen(NSWindow)
    }

    private let kind: Kind
    private let action: () -> Void
    private var isPressed = false { didSet { needsDisplay = true } }
    var showsSymbol = false { didSet { needsDisplay = true } }

    init(kind: Kind, action: @escaping () -> Void) {
        self.kind = kind
        self.action = action
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not available")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var color: NSColor {
        switch kind {
        case .close: NSColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1)
        case .minimize: NSColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1)
        case .fullScreen: NSColor(srgbRed: 0.16, green: 0.78, blue: 0.25, alpha: 1)
        }
    }

    private var symbolName: String {
        switch kind {
        case .close: "xmark"
        case .minimize: "minus"
        case .fullScreen(let window):
            window.styleMask.contains(.fullScreen)
                ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        (isPressed ? color.blended(withFraction: 0.25, of: .black) ?? color : color).setFill()
        circle.fill()
        NSColor.black.withAlphaComponent(0.12).setStroke()
        circle.lineWidth = 0.5
        circle.stroke()

        guard showsSymbol,
              let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                  .withSymbolConfiguration(.init(pointSize: 7, weight: .bold))
        else { return }
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.black.withAlphaComponent(0.55).set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let origin = NSPoint(x: bounds.midX - symbol.size.width / 2, y: bounds.midY - symbol.size.height / 2)
        tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        guard isPressed else { return }
        isPressed = false
        action()
    }
}
