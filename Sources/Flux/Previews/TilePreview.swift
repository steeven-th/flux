import AppKit
import SwiftUI

/// A pinned tab's page, shown beside the sidebar while the pointer rests on its tile, like Arc's
/// previews. The page is the tab's own, live: it can be scrolled and clicked. A calendar's tile
/// also shows the next meeting from the Mac's calendars.
@MainActor
final class TilePreview {
    static let shared = TilePreview()

    private static let showDelay: TimeInterval = 0.6
    private static let hideDelay: TimeInterval = 0.25
    private static let size = NSSize(width: 440, height: 340)
    private static let inset: CGFloat = 6
    private static let gap: CGFloat = 14
    private static let cornerRadius = FLXPageCornerRadius + inset

    private var window: PreviewWindow?
    private weak var page: FLXBrowserView?
    private weak var tab: Tab?
    private var showWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?
    private var isMenuOpen = false

    /// A tile's menu, opened with the pointer on it, would otherwise let the preview come up
    /// under it.
    private init() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isMenuOpen = true
                self?.hide()
            }
        }
        center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isMenuOpen = false }
        }
    }

    /// The pointer entered or left a tile.
    func pointer(isOn: Bool, tab: Tab, tile: NSView, state: BrowserState) {
        if isOn {
            hideWork?.cancel()
            guard self.tab !== tab else { return }
            showWork?.cancel()
            let work = DispatchWorkItem { [weak self, weak tab, weak tile, weak state] in
                MainActor.assumeIsolated {
                    guard let self, let tab, let tile, let state else { return }
                    self.show(tab, beside: tile, state: state)
                }
            }
            showWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.showDelay, execute: work)
        } else {
            showWork?.cancel()
            scheduleHide()
        }
    }

    func hide() {
        showWork?.cancel()
        hideWork?.cancel()
        // A tile clicked meanwhile moved the page into the window's page area.
        if let page, page.window === window { page.removeFromSuperview() }
        if let window {
            window.parent?.removeChildWindow(window)
            window.orderOut(nil)
        }
        window = nil
        page = nil
        tab = nil
    }

    private func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let window = self.window else { return }
                if window.frame.contains(NSEvent.mouseLocation) { return }
                self.hide()
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideDelay, execute: work)
    }

    private func show(_ tab: Tab, beside tile: NSView, state: BrowserState) {
        // A tab a window shows is already in sight, and a drag is under way while a button is down.
        guard !isMenuOpen, NSEvent.pressedMouseButtons == 0, let host = tile.window,
              !state.isShownInAnyWindow(tab) else { return }
        hide()
        let tileFrame = host.convertToScreen(tile.convert(tile.bounds, to: nil))
        let calendar = CalendarSite.matches(tab.url)
        let headerHeight: CGFloat = calendar ? NextMeetingView.height : 0
        let size = NSSize(width: Self.size.width, height: Self.size.height + headerHeight)
        let window = PreviewWindow(contentRect: frame(for: size, beside: tileFrame, state: state), styleMask: [.borderless], backing: .buffered, defer: false)
        window.onPointerExit = { [weak self] in self?.scheduleHide() }
        window.onPointerEnter = { [weak self] in self?.hideWork?.cancel() }
        let container = WindowBackgroundView(cornerRadius: Self.cornerRadius)
        window.contentView = container

        if calendar {
            let header = NSHostingView(rootView: NextMeetingView(agenda: CalendarAgenda.shared) { url in
                state.newTab(url: url.absoluteString)
            })
            header.frame = NSRect(x: 0, y: container.bounds.height - headerHeight, width: container.bounds.width, height: headerHeight)
            header.autoresizingMask = [.width, .minYMargin]
            container.addSubview(header)
            CalendarAgenda.shared.refresh()
        }

        let page = tab.browserView
        page.frame = NSRect(
            x: Self.inset, y: Self.inset,
            width: container.bounds.width - 2 * Self.inset,
            height: container.bounds.height - headerHeight - 2 * Self.inset + (calendar ? Self.inset : 0)
        )
        page.autoresizingMask = [.width, .height]
        // Above the overlay sidebar too, which is itself a child window.
        (host.parent ?? host).addChildWindow(window, ordered: .above)
        container.addSubview(page)
        window.alphaValue = 0
        window.animator().alphaValue = 1
        window.trackPointer()
        self.window = window
        self.page = page
        self.tab = tab
    }

    /// Beside the sidebar, its top level with the tile's, kept on the screen.
    private func frame(for size: NSSize, beside tile: NSRect, state: BrowserState) -> NSRect {
        let isOnRight = state.sidebarSide == .right
        var origin = NSPoint(
            x: isOnRight ? tile.minX - Self.gap - size.width - 12 : tile.maxX + Self.gap + 12,
            y: tile.maxY - size.height
        )
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(tile) })?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
            origin.y = min(max(origin.y, screen.minY), screen.maxY - size.height)
        }
        return NSRect(origin: origin, size: size)
    }
}

private final class PreviewWindow: NSWindow {
    var onPointerEnter: (() -> Void)?
    var onPointerExit: (() -> Void)?

    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }

    func trackPointer() {
        guard let view = contentView else { return }
        view.addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onPointerExit?()
    }
}
