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

    private let page: FLXBrowserView
    private var anchorTopLeft = NSPoint.zero

    static func show(url: String, profile: FLXProfile, below anchor: NSView) {
        current?.close()
        let panel = ExtensionPopupPanel(url: url, profile: profile)
        panel.present(below: anchor)
        current = panel
    }

    private init(url: String, profile: FLXProfile) {
        page = FLXBrowserView(embeddedWithURL: url, profile: profile)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
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
        page.frame = container.bounds
        page.autoresizingMask = [.width, .height]
        container.addSubview(page)
        contentView = container

        page.delegate = self
        page.fitToContent(withMinimumSize: Self.minimumSize, maximumSize: Self.maximumSize)
    }

    override var canBecomeKey: Bool { true }

    private func present(below anchor: NSView) {
        guard let anchorWindow = anchor.window else { return }
        let anchorFrame = anchorWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        anchorTopLeft = NSPoint(x: anchorFrame.minX, y: anchorFrame.minY - 6)
        setFrameTopLeftPoint(anchorTopLeft)
        makeKeyAndOrderFront(nil)
        page.focus()
    }

    override func resignKey() {
        super.resignKey()
        close()
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func close() {
        page.close()
        super.close()
    }
}

extension ExtensionPopupPanel: FLXBrowserViewDelegate {
    func browserView(_ browserView: FLXBrowserView, didResizeToFit size: NSSize) {
        var frame = self.frame
        frame.size = size
        frame.origin = NSPoint(x: anchorTopLeft.x, y: anchorTopLeft.y - size.height)
        setFrame(frame, display: true)
    }

    func browserViewDidClose(_ browserView: FLXBrowserView) {
        close()
    }
}
