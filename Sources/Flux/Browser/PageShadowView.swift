import AppKit

/// A light shadow under a page, drawn in Flux's window rather than by the page's: the system gives
/// the key window a much larger one.
final class PageShadowView: NSView {
    static let outset: CGFloat = 16

    /// The shapes to shadow, in the view's coordinates, when the page area holds several pages.
    var shapes: [NSRect]? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let page = bounds.insetBy(dx: Self.outset, dy: Self.outset)
        // The page's shape is drawn far outside the view, and only its shadow is moved back under
        // the page. Drawing the shape here and clearing it would leave its antialiased edge around
        // the page's corners.
        let away: CGFloat = 4 * (bounds.width + bounds.height)
        context.setShadow(
            offset: CGSize(width: away, height: 0),
            blur: 5,
            color: NSColor.black.withAlphaComponent(0.15).cgColor
        )
        context.translateBy(x: -away, y: 0)
        for shape in shapes ?? [page] {
            context.addPath(CGPath(
                roundedRect: shape, cornerWidth: FLXPageCornerRadius, cornerHeight: FLXPageCornerRadius, transform: nil
            ))
        }
        context.fillPath()
    }
}
