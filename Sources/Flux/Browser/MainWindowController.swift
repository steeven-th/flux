import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController {
    private static let defaultSidebarWidth: CGFloat = 260
    private static let sidebarWidths: ClosedRange<CGFloat> = 200...480
    private static let pageMargin: CGFloat = 8
    private static let resizeHandleWidth: CGFloat = 6

    private let state: BrowserState
    private let content = NSView()
    private lazy var sidebar: NSView = NSHostingView(rootView: SidebarView(state: state) { [weak self] target in
        self?.showCommandBar(target)
    })
    private let pageContainer = NSView()
    private let pageShadow = PageShadowView()
    private let resizeHandle = SidebarResizeHandle()
    private let revealEdge = SidebarRevealEdge()
    private var overlay: SidebarOverlayWindow?
    private var peekPresenter: PeekPresenter?
    private var sidebarConstraints: [NSLayoutConstraint] = []
    private var pageLeading: NSLayoutConstraint!
    private var handleLeading: NSLayoutConstraint!
    private var sidebarWidth: CGFloat

    init(state: BrowserState) {
        self.state = state
        sidebarWidth = state.sidebarWidth.map { $0.clamped(to: Self.sidebarWidths) } ?? Self.defaultSidebarWidth
        let window = MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()
        super.init(window: window)

        let background = NSHostingView(rootView: SpaceBackground(state: state))
        for view in [background, pageShadow, pageContainer, resizeHandle, revealEdge] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        content.addSubview(background)
        content.addSubview(pageShadow)
        content.addSubview(pageContainer)
        content.addSubview(resizeHandle)
        content.addSubview(revealEdge)
        window.contentView = content

        pageLeading = pageContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor)
        handleLeading = resizeHandle.leadingAnchor.constraint(equalTo: content.leadingAnchor)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            background.topAnchor.constraint(equalTo: content.topAnchor),
            background.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            // The page sits in its own window above this one, so the title bar doesn't cover it.
            pageLeading,
            pageContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.pageMargin),
            pageContainer.topAnchor.constraint(equalTo: content.topAnchor, constant: Self.pageMargin),
            pageContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Self.pageMargin),
            pageShadow.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor, constant: -PageShadowView.outset),
            pageShadow.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor, constant: PageShadowView.outset),
            pageShadow.topAnchor.constraint(equalTo: pageContainer.topAnchor, constant: -PageShadowView.outset),
            pageShadow.bottomAnchor.constraint(equalTo: pageContainer.bottomAnchor, constant: PageShadowView.outset),
            handleLeading,
            resizeHandle.widthAnchor.constraint(equalToConstant: Self.resizeHandleWidth),
            resizeHandle.topAnchor.constraint(equalTo: content.topAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            revealEdge.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            revealEdge.widthAnchor.constraint(equalToConstant: Self.pageMargin),
            revealEdge.topAnchor.constraint(equalTo: content.topAnchor),
            revealEdge.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        resizeHandle.onDrag = { [weak self] delta in self?.resizeSidebar(by: delta) }
        resizeHandle.onEnd = { [weak self] in
            guard let self else { return }
            self.state.sidebarWidth = self.sidebarWidth
        }
        revealEdge.onEnter = { [weak self] in self?.showOverlay() }
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.overlay?.updateFrame(self.overlayFrame)
                self.peekPresenter?.updateFrame(self.pageArea)
            }
        }
        peekPresenter = PeekPresenter(host: window, state: state)

        if state.isSidebarCollapsed {
            collapse(animated: false)
        } else {
            expand(animated: false)
        }
        showSelectedTab()
        observeSelectedTab()
        observePeek()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not available")
    }

    func toggleSidebar() {
        if state.isSidebarCollapsed {
            expand(animated: true)
        } else {
            collapse(animated: true)
        }
    }

    // Pages resize slowly, so they never resize during the animation: the sidebar slides over the
    // page, which takes its new width once, before the sidebar slides out or after it slid in.
    private func expand(animated: Bool) {
        state.isSidebarCollapsed = false
        revealEdge.isHidden = true
        guard animated, let overlay else { return dock() }
        overlay.hidesWhenPointerLeaves = false
        overlay.show(frame: overlayFrame) { [weak self] in
            guard let self, !self.state.isSidebarCollapsed else { return }
            self.dock()
        }
    }

    private func dock() {
        overlay?.hide(animated: false)
        overlay?.hidesWhenPointerLeaves = true
        sidebar.removeFromSuperview()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sidebar, positioned: .below, relativeTo: pageContainer)
        sidebarConstraints = [
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: sidebarWidth),
        ]
        NSLayoutConstraint.activate(sidebarConstraints)
        setWindowButtonsHidden(false)
        resizeHandle.isHidden = false
        handleLeading.constant = sidebarWidth - Self.resizeHandleWidth
        pageLeading.constant = sidebarWidth
    }

    private func collapse(animated: Bool) {
        state.isSidebarCollapsed = true
        NSLayoutConstraint.deactivate(sidebarConstraints)
        sidebarConstraints = []
        if overlay == nil, let window {
            let overlay = SidebarOverlayWindow(state: state, host: window)
            overlay.keepsShowingIn = { [weak self] in
                guard let self, let window = self.window else { return .zero }
                return window.convertToScreen(self.revealEdge.convert(self.revealEdge.bounds, to: nil))
            }
            self.overlay = overlay
        }
        guard let overlay else { return }
        overlay.hidesWhenPointerLeaves = true
        overlay.setFrame(overlayFrame, display: false)
        overlay.hold(sidebar)
        // The page covers the title bar now, the overlay shows its own window buttons.
        setWindowButtonsHidden(true)
        resizeHandle.isHidden = true
        revealEdge.isHidden = false
        pageLeading.constant = Self.pageMargin
        if animated {
            overlay.show(frame: overlayFrame, animated: false)
            overlay.hide()
        }
    }

    private func showOverlay() {
        guard state.isSidebarCollapsed else { return }
        overlay?.show(frame: overlayFrame)
    }

    private var overlayFrame: NSRect {
        guard let window else { return .zero }
        let area = window.frame
        return NSRect(
            x: area.minX + SidebarOverlayWindow.inset,
            y: area.minY + SidebarOverlayWindow.inset,
            width: sidebarWidth,
            height: area.height - SidebarOverlayWindow.inset * 2
        )
    }

    private func resizeSidebar(by delta: CGFloat) {
        sidebarWidth = (sidebarWidth + delta).clamped(to: Self.sidebarWidths)
        sidebarConstraints.last?.constant = sidebarWidth
        handleLeading.constant = sidebarWidth - Self.resizeHandleWidth
        pageLeading.constant = sidebarWidth
    }

    private func setWindowButtonsHidden(_ hidden: Bool) {
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window?.standardWindowButton(type)?.isHidden = hidden
        }
    }

    func showCommandBar(_ target: CommandBarModel.Target) {
        guard let window else { return }
        CommandBarPanel.show(target, state: state, over: window)
    }

    private var pageArea: NSRect {
        guard let window else { return .zero }
        return window.convertToScreen(pageContainer.convert(pageContainer.bounds, to: nil))
    }

    private func observePeek() {
        withObservationTracking {
            _ = state.peek
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if let peek = self.state.peek {
                    self.peekPresenter?.show(peek, over: self.pageArea, dimming: self.state.selectedTab?.browserView)
                } else {
                    self.peekPresenter?.hide()
                }
                self.observePeek()
            }
        }
    }

    /// Pages of other tabs stay alive. Only the selected one is in the view hierarchy.
    private func showSelectedTab() {
        // A Peek belongs to the tab it was opened from.
        if state.peek != nil { state.closePeek() }
        defer { if overlay?.isShown == true { showOverlay() } }
        let selected = state.selectedTab?.browserView
        pageShadow.isHidden = selected == nil
        for view in pageContainer.subviews where view !== selected {
            view.removeFromSuperview()
        }
        guard let selected, selected.superview !== pageContainer else { return }
        selected.frame = pageContainer.bounds
        selected.autoresizingMask = [.width, .height]
        pageContainer.addSubview(selected)
        selected.focus()
    }

    private func observeSelectedTab() {
        withObservationTracking {
            _ = state.selectedTab
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.showSelectedTab()
                self?.observeSelectedTab()
            }
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
