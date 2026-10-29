import AppKit
import SwiftUI

/// Shows the Peek's card over the page area, with the page under it dimmed. A clear window between
/// the two closes the Peek when clicked. These are windows, since the pages under them are windows
/// too. The dimming is drawn inside the page's own window: a window over it never lines up exactly
/// with its rounded corners.
@MainActor
final class PeekPresenter {
    private static let barHeight: CGFloat = 36
    private static let pageInset: CGFloat = 6
    // Concentric with the page's corners.
    private static let cornerRadius = FLXPageCornerRadius + pageInset

    private weak var host: NSWindow?
    private let state: BrowserState
    private var backdrop: NSWindow?
    private var card: NSWindow?
    private weak var page: FLXBrowserView?
    private weak var dimmedPage: FLXBrowserView?

    init(host: NSWindow, state: BrowserState) {
        self.host = host
        self.state = state
    }

    func show(_ peek: Peek, over area: NSRect, dimming pageBehind: FLXBrowserView?) {
        hide()
        guard let host else { return }
        pageBehind?.isDimmed = true
        dimmedPage = pageBehind

        let backdrop = BackdropWindow { [weak state] in state?.closePeek() }
        backdrop.setFrame(area, display: false)
        host.addChildWindow(backdrop, ordered: .above)

        let card = CardWindow(contentRect: cardFrame(in: area), styleMask: [.borderless], backing: .buffered, defer: false)
        card.isReleasedWhenClosed = false
        card.isOpaque = false
        card.backgroundColor = .clear
        card.hasShadow = true
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.cornerRadius = Self.cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        card.contentView = container

        let bar = NSHostingView(rootView: PeekBar(peek: peek, state: state))
        bar.frame = NSRect(x: 0, y: container.bounds.height - Self.barHeight, width: container.bounds.width, height: Self.barHeight)
        bar.autoresizingMask = [.width, .minYMargin]
        container.addSubview(bar)

        let page = peek.page
        page.frame = NSRect(
            x: Self.pageInset, y: Self.pageInset,
            width: container.bounds.width - 2 * Self.pageInset,
            height: container.bounds.height - Self.barHeight - Self.pageInset
        )
        page.autoresizingMask = [.width, .height]
        host.addChildWindow(card, ordered: .above)
        container.addSubview(page)

        card.alphaValue = 0
        card.animator().alphaValue = 1
        card.makeKey()
        page.focus()
        self.backdrop = backdrop
        self.card = card
        self.page = page
    }

    func hide() {
        // After "Open in Tab", the page already lives in the window's page area.
        if let page, page.window === card { page.removeFromSuperview() }
        for window in [card, backdrop].compactMap({ $0 }) {
            window.parent?.removeChildWindow(window)
            window.orderOut(nil)
        }
        dimmedPage?.isDimmed = false
        card = nil
        backdrop = nil
        page = nil
        dimmedPage = nil
    }

    func updateFrame(_ area: NSRect) {
        backdrop?.setFrame(area, display: true)
        card?.setFrame(cardFrame(in: area), display: true)
    }

    private func cardFrame(in area: NSRect) -> NSRect {
        area.insetBy(dx: area.width * 0.05, dy: area.height * 0.04)
    }
}

private final class CardWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class BackdropWindow: NSWindow {
    init(onClick: @escaping () -> Void) {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Clear, but still taking clicks.
        ignoresMouseEvents = false
        contentView = ClickView(onClick: onClick)
    }

    private final class ClickView: NSView {
        let onClick: () -> Void

        init(onClick: @escaping () -> Void) {
            self.onClick = onClick
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not available")
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            onClick()
        }
    }
}

private struct PeekBar: View {
    let peek: Peek
    let state: BrowserState

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let favicon = peek.favicon {
                    Image(nsImage: favicon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "globe").foregroundStyle(.secondary)
                }
            }
            .frame(width: 16, height: 16)
            Text(host)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                state.openPeekInTab()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .help("Open in Tab")
            Button {
                state.closePeek()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .help("Close (⌘W)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
    }

    private var host: String {
        guard let host = URL(string: peek.url)?.host() else { return peek.url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
