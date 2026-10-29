import AppKit
import SwiftUI

/// The collapsed sidebar, shown over the page while the pointer is on it, like in Arc.
///
/// A child window of Flux's window: pages are windows too, so a view could never cover them.
@MainActor
final class SidebarOverlayWindow: NSWindow {
    /// The overlay sits this far inside Flux's window.
    static let inset: CGFloat = 4
    // Concentric with the window's own corners, which got rounder in macOS 26.
    private static var cornerRadius: CGFloat {
        let windowRadius: CGFloat = ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        ) ? 16 : 10
        return windowRadius - inset
    }
    private static let hideDelay: TimeInterval = 0.3
    private static let slideDuration: TimeInterval = 0.2

    private let container = NSView()
    private var trackingArea: NSTrackingArea?
    private var hideWork: DispatchWorkItem?
    private var isMenuOpen = false
    /// Whether the overlay is shown or sliding in, as opposed to hidden or sliding out.
    private(set) var isShown = false
    /// Off while the overlay brings the sidebar back into Flux's window.
    var hidesWhenPointerLeaves = true
    /// Where the pointer can be without the overlay hiding, besides the overlay itself.
    var keepsShowingIn: (() -> NSRect)?
    private weak var host: NSWindow?
    private var windowControls: WindowControls?

    init(state: BrowserState, host: NSWindow) {
        self.host = host
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let material = NSVisualEffectView()
        material.material = .sidebar
        material.state = .active
        material.autoresizingMask = [.width, .height]
        let tint = NSHostingView(rootView: SpaceBackground(state: state))
        tint.autoresizingMask = [.width, .height]

        container.wantsLayer = true
        container.autoresizingMask = [.width, .height]
        container.layer?.cornerRadius = Self.cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.addSubview(material)
        container.addSubview(tint)
        let root = NSView()
        container.frame = root.bounds
        root.addSubview(container)
        contentView = root

        let center = NotificationCenter.default
        center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isMenuOpen = true }
        }
        center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isMenuOpen = false
                self?.hideIfPointerLeft()
            }
        }
    }

    override var canBecomeKey: Bool { true }

    /// The sidebar view moves in here while collapsed, so it keeps its state.
    func hold(_ sidebar: NSView) {
        sidebar.removeFromSuperview()
        sidebar.translatesAutoresizingMaskIntoConstraints = true
        sidebar.frame = container.bounds
        sidebar.autoresizingMask = [.width, .height]
        container.addSubview(sidebar)
        addWindowButtons()
    }

    /// Slides in from Flux's window edge. The overlay window doesn't move, its content does, so
    /// nothing shows outside Flux's window.
    func show(frame: NSRect, animated: Bool = true, completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard let host else { return }
        hideWork?.cancel()
        isShown = true
        // Added again each time, so it goes above page windows added since.
        host.removeChildWindow(self)
        host.addChildWindow(self, ordered: .above)
        setFrame(frame, display: true)
        if !isVisible { container.setFrameOrigin(NSPoint(x: -frame.width, y: 0)) }
        updateTrackingArea()
        orderFront(nil)
        slide(toX: 0, animated: animated, completion: completion)
    }

    func hide(animated: Bool = true) {
        hideWork?.cancel()
        isShown = false
        guard animated, isVisible else { return remove() }
        slide(toX: -frame.width, animated: true) { [weak self] in
            guard let self, !self.isShown else { return }
            self.remove()
        }
    }

    private func remove() {
        parent?.removeChildWindow(self)
        orderOut(nil)
    }

    private func slide(toX x: CGFloat, animated: Bool, completion: (@MainActor @Sendable () -> Void)? = nil) {
        // The window's shadow follows its content, but only when told to, so it is left out while
        // the content moves.
        hasShadow = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? Self.slideDuration : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            container.animator().setFrameOrigin(NSPoint(x: x, y: 0))
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                if let self, self.isShown {
                    self.hasShadow = true
                    self.invalidateShadow()
                }
                completion?()
            }
        }
    }

    func updateFrame(_ frame: NSRect) {
        guard isShown else { return }
        setFrame(frame, display: true)
        updateTrackingArea()
    }

    private func updateTrackingArea() {
        if let trackingArea { container.removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: container.bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil
        )
        container.addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hideWork?.cancel()
    }

    override func mouseExited(with event: NSEvent) {
        hideIfPointerLeft()
    }

    private func hideIfPointerLeft() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isShown, self.hidesWhenPointerLeaves, !self.isMenuOpen else { return }
                let pointer = NSEvent.mouseLocation
                if self.frame.contains(pointer) || self.keepsShowingIn?().contains(pointer) == true { return }
                self.hide()
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideDelay, execute: work)
    }

    /// Flux's own window buttons sit under the page while the sidebar is collapsed, so the overlay
    /// shows copies that act on Flux's window.
    private func addWindowButtons() {
        guard let host else { return }
        windowControls?.removeFromSuperview()
        let controls = WindowControls(for: host)
        controls.setFrameOrigin(NSPoint(x: 13, y: container.bounds.height - 20))
        controls.autoresizingMask = [.maxXMargin, .minYMargin]
        container.addSubview(controls)
        windowControls = controls
    }
}

/// The sidebar's right edge, dragged to resize it.
final class SidebarResizeHandle: NSView {
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?
    private var isDragging = false
    private var isHovered = false

    // A tracking area rather than a cursor rect: cursor rects only work in the key window, which
    // is often the page's.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways], owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSCursor.resizeLeftRight.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        if !isDragging { NSCursor.arrow.set() }
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        NSCursor.resizeLeftRight.set()
    }

    override func mouseDragged(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
        onDrag?(event.deltaX)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        if !isHovered { NSCursor.arrow.set() }
        onEnd?()
    }
}

/// The strip along the window's left edge that brings the collapsed sidebar back.
final class SidebarRevealEdge: NSView {
    var onEnter: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter?()
    }
}
