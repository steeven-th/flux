import AppKit

/// Where the panes of a split go in the page area.
enum SplitLayout {
    static let gap: CGFloat = 8
    static let minimumPane: CGFloat = 200

    /// Parts in pane order that add up to 1. Nil parts share equally what the others leave.
    static func normalized(_ shares: [Double?]) -> [Double] {
        guard !shares.isEmpty else { return [] }
        let known = shares.compactMap { $0 }.reduce(0, +)
        let missing = shares.filter { $0 == nil }.count
        let rest = missing > 0 ? max(1 - known, 0) / Double(missing) : 0
        let values = shares.map { $0 ?? rest }
        let total = values.reduce(0, +)
        guard total > 0 else { return Array(repeating: 1 / Double(shares.count), count: shares.count) }
        return values.map { $0 / total }
    }

    /// Side by side from the left, or stacked from the top.
    static func frames(in bounds: NSRect, shares: [Double], isVertical: Bool) -> [NSRect] {
        let length = (isVertical ? bounds.height : bounds.width) - gap * CGFloat(shares.count - 1)
        var offset: CGFloat = 0
        return shares.enumerated().map { index, share in
            // The last pane takes what rounding left.
            let size = index == shares.count - 1 ? length - offset : (length * share).rounded()
            let start = offset + gap * CGFloat(index)
            defer { offset += size }
            return isVertical
                ? NSRect(x: bounds.minX, y: bounds.maxY - start - size, width: bounds.width, height: size)
                : NSRect(x: bounds.minX + start, y: bounds.minY, width: size, height: bounds.height)
        }
    }

    /// Moves the line after pane `index` by `delta` points, keeping both panes wide enough. Two
    /// panes snap to equal parts near the middle, like in Arc.
    static func resized(_ shares: [Double], after index: Int, by delta: CGFloat, length: CGFloat) -> [Double] {
        let available = length - gap * CGFloat(shares.count - 1)
        guard available > 0, shares.indices.contains(index + 1) else { return shares }
        var sizes = shares.map { CGFloat($0) * available }
        let pair = sizes[index] + sizes[index + 1]
        var first = min(max(sizes[index] + delta, minimumPane), pair - minimumPane)
        if shares.count == 2, abs(first - pair / 2) < 12 { first = pair / 2 }
        sizes[index] = first
        sizes[index + 1] = pair - first
        return sizes.map { Double($0 / available) }
    }
}

/// The line between two panes, which resizes them. A double click gives them equal parts.
final class SplitHandleView: NSView {
    var isVertical = false
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?
    var onReset: (() -> Void)?

    private var isHovered = false {
        didSet { needsDisplay = true }
    }
    private var isDragging = false

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: isVertical ? .resizeUpDown : .resizeLeftRight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { if !isDragging { isHovered = false } }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onReset?() }
    }

    override func mouseDragged(with event: NSEvent) {
        isDragging = true
        // Down grows the pane above, AppKit's y goes up.
        onDrag?(isVertical ? -event.deltaY : event.deltaX)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        isHovered = bounds.contains(convert(event.locationInWindow, from: nil))
        onEnd?()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHovered || isDragging else { return }
        let pill = isVertical
            ? NSRect(x: bounds.midX - 18, y: bounds.midY - 2, width: 36, height: 4)
            : NSRect(x: bounds.midX - 2, y: bounds.midY - 18, width: 4, height: 36)
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 2, yRadius: 2).fill()
    }
}
