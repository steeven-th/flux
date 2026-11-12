import AppKit

/// Shows an extension's popup page under its toolbar icon, sized to the page like in Chrome.
///
/// A plain opaque panel rather than an NSPopover: popovers apply vibrancy to their content, which
/// washes out the page.
@MainActor
final class ExtensionPopupPanel: NSPanel {
    // Chrome's limits for extension popups.
    private static let minimumSize = NSSize(width: 25, height: 25)
    private static let maximumSize = NSSize(width: 800, height: 600)
    private static let cornerRadius: CGFloat = 10

    private static weak var current: ExtensionPopupPanel?

    private let popup: FLXExtensionPopup
    private var anchorTopLeft = NSPoint.zero

    static func show(_ popup: FLXExtensionPopup, below anchor: NSView) {
        current?.close()
        let panel = ExtensionPopupPanel(popup: popup)
        panel.present(below: anchor)
        current = panel
    }

    private init(popup: FLXExtensionPopup) {
        self.popup = popup
        let size = NSSize(width: max(popup.size.width, Self.minimumSize.width), height: max(popup.size.height, Self.minimumSize.height))
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        level = .popUpMenu

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.cornerRadius = Self.cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        popup.view.frame = container.bounds
        popup.view.autoresizingMask = [.width, .height]
        container.addSubview(popup.view)
        contentView = container

        popup.onResize = { [weak self] size in self?.resize(to: size) }
        popup.onClose = { [weak self] in self?.close() }
    }

    private func resize(to size: NSSize) {
        var frame = self.frame
        frame.size = size
        frame.origin = NSPoint(x: anchorTopLeft.x, y: anchorTopLeft.y - size.height)
        setFrame(frame, display: true)
    }

    override var canBecomeKey: Bool { true }

    private func present(below anchor: NSView) {
        guard let anchorWindow = anchor.window else { return }
        let anchorFrame = anchorWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        anchorTopLeft = NSPoint(x: anchorFrame.minX, y: anchorFrame.minY - 6)
        setFrameTopLeftPoint(anchorTopLeft)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(popup.view)
    }

    override func resignKey() {
        super.resignKey()
        close()
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func close() {
        popup.onClose = nil
        popup.close()
        super.close()
    }
}
