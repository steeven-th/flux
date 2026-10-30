import AppKit

/// Where a tab dragged from the sidebar onto the pages goes: in a new pane beside one, or in
/// place of one.
enum SplitDropTarget: Equatable {
    case insert(beside: Tab, after: Bool, isVertical: Bool)
    case replace(Tab)
}

/// Takes the drop of a tab dragged from the sidebar onto the page area. Pages are windows that
/// would take the drag themselves, so this one goes over them for the time of the drag.
@MainActor
final class SplitDropOverlay {
    /// The shown tabs with their frames, in the page area's coordinates.
    var panes: () -> [(tab: Tab, frame: NSRect)] = { [] }
    /// Nil for a single page, which can be split either way.
    var isVertical: () -> Bool? = { nil }
    var tab: (UUID) -> Tab? = { _ in nil }
    var canDrop: (Tab, SplitDropTarget) -> Bool = { _, _ in false }
    var onDrop: (Tab, SplitDropTarget) -> Void = { _, _ in }

    private let window: NSWindow
    private let dropView = SplitDropView()

    init() {
        window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        // Fully clear windows let the pointer through to the windows below.
        window.backgroundColor = NSColor.black.withAlphaComponent(0.001)
        window.hasShadow = false
        window.contentView = dropView
        dropView.overlay = self
    }

    func show(frame: NSRect, over host: NSWindow) {
        host.removeChildWindow(window)
        window.setFrame(frame, display: true)
        host.addChildWindow(window, ordered: .above)
    }

    func hide() {
        dropView.clear()
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
    }

    /// The edges of a pane insert a new pane on that side, its middle replaces it. Edges only
    /// along the split's direction, and none once the split is full.
    fileprivate func target(for tab: Tab, at point: NSPoint) -> (SplitDropTarget, NSRect)? {
        let panes = panes()
        guard let pane = panes.first(where: { $0.frame.contains(point) }), pane.tab !== tab else { return nil }
        let frame = pane.frame
        let isVertical = isVertical()
        let x = (point.x - frame.minX) / frame.width
        let y = (point.y - frame.minY) / frame.height
        let edge = 0.25
        var candidates: [(SplitDropTarget, NSRect)] = []
        if isVertical != true {
            if x < edge { candidates.append((.insert(beside: pane.tab, after: false, isVertical: false), frame.divided(atDistance: frame.width / 2, from: .minXEdge).slice)) }
            if x > 1 - edge { candidates.append((.insert(beside: pane.tab, after: true, isVertical: false), frame.divided(atDistance: frame.width / 2, from: .maxXEdge).slice)) }
        }
        if isVertical != false {
            // AppKit's y goes up: the top of the pane is near 1.
            if y > 1 - edge { candidates.append((.insert(beside: pane.tab, after: false, isVertical: true), frame.divided(atDistance: frame.height / 2, from: .maxYEdge).slice)) }
            if y < edge { candidates.append((.insert(beside: pane.tab, after: true, isVertical: true), frame.divided(atDistance: frame.height / 2, from: .minYEdge).slice)) }
        }
        candidates.append((.replace(pane.tab), frame))
        return candidates.first { canDrop(tab, $0.0) }
    }

    fileprivate func tab(in info: NSDraggingInfo) -> Tab? {
        guard let string = info.draggingPasteboard.string(forType: SidebarOutline.Coordinator.dragType),
              let id = UUID(uuidString: string) else { return nil }
        return tab(id)
    }

    fileprivate func drop(_ tab: Tab, on target: SplitDropTarget) {
        onDrop(tab, target)
    }
}

private final class SplitDropView: NSView {
    weak var overlay: SplitDropOverlay?
    private let indicator = NSView()
    private var target: SplitDropTarget?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([SidebarOutline.Coordinator.dragType])
        indicator.wantsLayer = true
        indicator.layer?.cornerRadius = FLXPageCornerRadius
        indicator.layer?.borderWidth = 2
        indicator.isHidden = true
        addSubview(indicator)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not available")
    }

    func clear() {
        target = nil
        indicator.isHidden = true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let overlay, let tab = overlay.tab(in: sender),
              let (target, frame) = overlay.target(for: tab, at: convert(sender.draggingLocation, from: nil)) else {
            clear()
            return []
        }
        show(frame.insetBy(dx: 4, dy: 4), isNew: self.target == nil)
        self.target = target
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        clear()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let target, let tab = overlay?.tab(in: sender) else { return false }
        clear()
        overlay?.drop(tab, on: target)
        return true
    }

    /// The zone opens from its edge the first time, then slides as the pointer moves.
    private func show(_ frame: NSRect, isNew: Bool) {
        let accent = NSColor.controlAccentColor
        indicator.layer?.backgroundColor = accent.withAlphaComponent(0.18).cgColor
        indicator.layer?.borderColor = accent.withAlphaComponent(0.7).cgColor
        if isNew {
            indicator.frame = NSRect(x: frame.midX, y: frame.midY, width: 0, height: 0)
            indicator.isHidden = false
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            indicator.animator().frame = frame
        }
    }
}
