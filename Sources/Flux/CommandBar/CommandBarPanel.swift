import AppKit
import SwiftUI

/// The command bar, floating over the top of Flux's window like in Arc.
///
/// A child window of Flux's window, so it stays above the page windows and Flux's window keeps
/// looking active while the bar has the keyboard.
@MainActor
final class CommandBarPanel: NSPanel {
    private static let maximumWidth: CGFloat = 640
    private static let cornerRadius: CGFloat = 12
    /// Room around the bar for its shadow, which AppKit's window shadow keeps too tight.
    private static let shadowMargin: CGFloat = 48
    private static weak var current: CommandBarPanel?

    private let model: CommandBarModel

    static func show(_ target: CommandBarModel.Target, state: BrowserState, over window: NSWindow) {
        current?.close()
        let panel = CommandBarPanel(model: CommandBarModel(state: state, target: target))
        panel.present(over: window)
        current = panel
    }

    private init(model: CommandBarModel) {
        self.model = model
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        hasShadow = false
        isOpaque = false
        backgroundColor = .clear

        contentView = BarContainer(
            content: NSHostingView(rootView: CommandBarView(model: model)),
            margin: Self.shadowMargin,
            cornerRadius: Self.cornerRadius
        )
        model.onFinish = { [weak self] in self?.close() }
    }

    override var canBecomeKey: Bool { true }

    private func present(over window: NSWindow) {
        window.addChildWindow(self, ordered: .above)
        updateFrame()
        makeKeyAndOrderFront(nil)
        observeSuggestions()
    }

    private func updateFrame() {
        guard let parent else { return }
        let area = parent.frame
        let width = min(Self.maximumWidth, area.width - 80)
        let height = CommandBarView.height(forRows: model.suggestions.count)
        let top = area.maxY - max(80, area.height * 0.18)
        let bar = NSRect(x: area.midX - width / 2, y: top - height, width: width, height: height)
        setFrame(bar.insetBy(dx: -Self.shadowMargin, dy: -Self.shadowMargin), display: true)
    }

    private func observeSuggestions() {
        withObservationTracking {
            _ = model.suggestions
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateFrame()
                self?.observeSuggestions()
            }
        }
    }

    // Handled here, before the text field sees them, unless an input method is composing text.
    override func sendEvent(_ event: NSEvent) {
        let composing = (firstResponder as? NSTextView)?.hasMarkedText() ?? false
        if event.type == .keyDown, !composing {
            switch event.keyCode {
            case 125:
                model.moveSelection(by: 1)
                return
            case 126:
                model.moveSelection(by: -1)
                return
            case 36, 76:
                model.performSelected(inBackground: event.modifierFlags.contains(.command))
                return
            case 53:
                close()
                return
            default:
                break
            }
        }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        close()
    }

    override func close() {
        parent?.removeChildWindow(self)
        super.close()
    }
}

/// The bar, inset by a margin that leaves room for its shadow. Frames are set on each layout: the
/// panel starts at zero size, which autoresizing can't recover from.
private final class BarContainer: NSView {
    private let margin: CGFloat
    private let shadowShape = NSView()
    private let background = NSVisualEffectView()
    private let content: NSView

    init(content: NSView, margin: CGFloat, cornerRadius: CGFloat) {
        self.content = content
        self.margin = margin
        super.init(frame: .zero)

        // The bar's material clips to its corners, so the shadow comes from a shape behind it.
        shadowShape.wantsLayer = true
        shadowShape.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        shadowShape.layer?.cornerRadius = cornerRadius
        shadowShape.layer?.cornerCurve = .continuous
        // Set through NSView: AppKit resets shadow values set on the layers it manages.
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 28
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadowShape.shadow = shadow

        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = cornerRadius
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true

        background.addSubview(content)
        addSubview(shadowShape)
        addSubview(background)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not available")
    }

    override func layout() {
        super.layout()
        let bar = bounds.insetBy(dx: margin, dy: margin)
        guard bar.width > 0, bar.height > 0 else { return }
        shadowShape.frame = bar
        background.frame = bar
        content.frame = background.bounds
    }
}
