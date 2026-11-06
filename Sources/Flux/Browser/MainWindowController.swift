import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private static let defaultSidebarWidth: CGFloat = 260
    private static let sidebarWidths: ClosedRange<CGFloat> = 200...480
    private static let pageMargin: CGFloat = 8
    private static let resizeHandleWidth: CGFloat = 6
    let state: BrowserState
    /// Called once the window closed.
    var onClose: (() -> Void)?
    private let content = NSView()
    private lazy var sidebar: NSView = {
        let view = NSHostingView(rootView: SidebarView(state: state) { [weak self] target in
            self?.showCommandBar(target)
        })
        // The sidebar's top row sits in the title bar, next to the window buttons.
        view.safeAreaRegions = []
        // Its content can be taller than the screen, with many favorites and the import's cards:
        // the window decides its size, and the outline scrolls.
        view.sizingOptions = []
        return view
    }()
    private let pageContainer = NSView()
    private let pageShadow = PageShadowView()
    /// By tab, for the tabs shown.
    private var panes: [UUID: PaneView] = [:]
    private var splitHandles: [SplitHandleView] = []
    /// The panes' parts while a handle is dragged, saved when it is released.
    private var liveShares: [Double]?
    private var paneClickMonitor: Any?
    private let dropOverlay = SplitDropOverlay()
    private let resizeHandle = SidebarResizeHandle()
    private let revealEdge = SidebarRevealEdge()
    private var overlay: SidebarOverlayWindow?
    private var peekPresenter: PeekPresenter?
    private var sidebarConstraints: [NSLayoutConstraint] = []
    private var pageLeading: NSLayoutConstraint!
    private var handleLeading: NSLayoutConstraint!
    private var sidebarWidth: CGFloat

    /// `frameName` saves the window's size and place, one per window. Private windows save
    /// nothing.
    init(state: BrowserState, frameName: String?) {
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
        // AppKit saves the window's size and place as it changes, and moves it back on screen if
        // that screen is gone.
        if let frameName {
            if !window.setFrameUsingName(frameName) { window.center() }
            window.setFrameAutosaveName(frameName)
        } else {
            window.center()
        }
        // Dark, so a private window isn't taken for another.
        if state.isPrivate { window.appearance = NSAppearance(named: .darkAqua) }
        super.init(window: window)
        window.delegate = self
        state.onShowWindow = { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }

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
            pageContainer.topAnchor.constraint(equalTo: content.topAnchor, constant: Self.pageMargin),
            pageContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.pageMargin),
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
                self.panes.values.forEach { $0.placeWindowsOverPage() }
            }
        }
        peekPresenter = PeekPresenter(host: window, state: state)
        let center = NotificationCenter.default
        for (name, isFullScreen) in [(NSWindow.didEnterFullScreenNotification, true), (NSWindow.didExitFullScreenNotification, false)] {
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.state.isWindowFullScreen = isFullScreen }
            }
        }

        // Before the first layout, which split panes need to follow.
        pageContainer.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: pageContainer, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.layoutPages() }
        }
        if state.isSidebarCollapsed {
            collapse(animated: false)
        } else {
            expand(animated: false)
        }
        showSelectedTab()
        observeSelectedTab()
        observeTitle()
        observePeek()
        observePanes()
        observeDraggedTab()
        // Pages are windows of their own, so a click in a pane only reaches Flux this way.
        paneClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, let window = event.window,
               let tab = self.state.shownTabs.first(where: { $0.browserView.pageWindow === window || $0.devTools?.pageWindow === window }),
               tab !== self.state.selectedTab {
                self.state.select(tab)
            }
            return event
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not available")
    }

    func windowWillClose(_ notification: Notification) {
        // Pages leave with their panes, so they live on for the tabs, in other windows.
        panes.values.forEach { $0.removeFromSuperview() }
        panes = [:]
        overlay?.hide(animated: false)
        dropOverlay.hide()
        if let paneClickMonitor { NSEvent.removeMonitor(paneClickMonitor) }
        paneClickMonitor = nil
        state.closeWindow()
        onClose?()
    }

    /// Hidden in the title bar, but listed in the Window menu.
    private func observeTitle() {
        let title = withObservationTracking {
            [state.selectedSpace.name, state.selectedTab?.displayTitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " – ")
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeTitle() }
        }
        window?.title = title
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

    private func showSelectedTab() {
        // A Peek belongs to the tab it was opened from.
        if state.peek != nil { state.closePeek() }
        defer { if overlay?.isShown == true { showOverlay() } }
        showPanes()
        state.selectedTab?.browserView.focus()
    }

    /// Pages of other tabs stay alive. Only the shown ones, the selected tab or its split's, are in
    /// the view hierarchy.
    private func showPanes() {
        let tabs = state.shownTabs
        for (id, pane) in panes where !tabs.contains(where: { $0.id == id }) {
            panes[id] = nil
            // Not for a tab being closed.
            guard state.tabs.contains(where: { $0 === pane.tab }) else {
                pane.removeFromSuperview()
                continue
            }
            // Some sites, Twitch among them, stop a muted stream as soon as the page is hidden. The
            // page stays shown under the new one until its video is in picture-in-picture, as in
            // Chrome, where picture-in-picture starts before the tab is hidden.
            var isRemoved = false
            let remove = { [weak self, weak pane] in
                guard !isRemoved, let pane else { return }
                isRemoved = true
                if self?.panes.values.contains(pane) != true { pane.removeFromSuperview() }
            }
            pane.tab.enterPictureInPicture(completion: remove)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: remove)
        }
        for tab in tabs {
            tab.exitPictureInPicture()
            let pane = panes[tab.id] ?? PaneView(tab: tab, state: state)
            panes[tab.id] = pane
            pane.isInSplit = tabs.count > 1
            if pane.superview !== pageContainer { pageContainer.addSubview(pane) }
        }
        layoutPages()
        // Page windows added since go above the handles.
        panes.values.forEach { $0.placeWindowsOverPage() }
    }

    private func observeDraggedTab() {
        let tab = withObservationTracking {
            state.draggedTab
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeDraggedTab() }
        }
        guard tab != nil, let window else { return dropOverlay.hide() }
        dropOverlay.panes = { [weak self] in
            guard let self else { return [] }
            return self.state.shownTabs.compactMap { tab in self.panes[tab.id].map { (tab, $0.frame) } }
        }
        dropOverlay.isVertical = { [weak self] in self?.state.selectedSplit?.isVertical }
        dropOverlay.tab = { [weak self] id in
            guard case .tab(let tab) = self?.state.entry(id: id) else { return nil }
            return tab
        }
        dropOverlay.canDrop = { [weak self] tab, target in self?.state.canDrop(tab, on: target) ?? false }
        dropOverlay.onDrop = { [weak self] tab, target in self?.state.drop(tab, on: target) }
        dropOverlay.show(frame: pageArea, over: window)
    }

    private func observePanes() {
        withObservationTracking {
            _ = state.shownTabs.map(\.id)
            _ = state.selectedSplit?.isVertical
            _ = state.sidebarRevision
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.showPanes()
                self?.observePanes()
            }
        }
    }

    private func layoutPages() {
        let tabs = state.shownTabs
        pageShadow.isHidden = tabs.isEmpty
        var frames = [pageContainer.bounds]
        if tabs.count > 1, let split = state.selectedSplit {
            let shares = liveShares ?? SplitLayout.normalized(tabs.map(\.node.share))
            frames = SplitLayout.frames(in: pageContainer.bounds, shares: shares, isVertical: split.isVertical)
            placeSplitHandles(between: frames, of: split)
        } else {
            splitHandles.forEach { $0.isHidden = true }
        }
        for (tab, frame) in zip(tabs, frames) {
            panes[tab.id]?.frame = frame
        }
        pageShadow.shapes = frames.map { pageShadow.convert($0, from: pageContainer) }
    }

    private func placeSplitHandles(between frames: [NSRect], of split: Split) {
        while splitHandles.count < frames.count - 1 {
            let handle = SplitHandleView()
            let index = splitHandles.count
            handle.onDrag = { [weak self] delta in self?.resizePanes(after: index, by: delta) }
            handle.onEnd = { [weak self] in
                guard let self, let shares = self.liveShares, let split = self.state.selectedSplit else { return }
                self.liveShares = nil
                self.state.setShares(shares, of: split)
            }
            handle.onReset = { [weak self] in
                guard let self, let split = self.state.selectedSplit else { return }
                let count = self.state.panes(of: split).count
                self.state.setShares(Array(repeating: 1 / Double(count), count: count), of: split)
                self.layoutPages()
            }
            content.addSubview(handle)
            splitHandles.append(handle)
        }
        for (index, handle) in splitHandles.enumerated() {
            guard index < frames.count - 1 else {
                handle.isHidden = true
                continue
            }
            let before = frames[index]
            let gap = split.isVertical
                ? NSRect(x: before.minX, y: before.minY - SplitLayout.gap, width: before.width, height: SplitLayout.gap)
                : NSRect(x: before.maxX, y: before.minY, width: SplitLayout.gap, height: before.height)
            handle.isVertical = split.isVertical
            handle.frame = content.convert(gap, from: pageContainer)
            handle.isHidden = false
            handle.window?.invalidateCursorRects(for: handle)
        }
    }

    private func resizePanes(after index: Int, by delta: CGFloat) {
        guard let split = state.selectedSplit else { return }
        let panes = state.shownTabs
        let shares = liveShares ?? SplitLayout.normalized(panes.map(\.node.share))
        let length = split.isVertical ? pageContainer.bounds.height : pageContainer.bounds.width
        liveShares = SplitLayout.resized(shares, after: index, by: delta, length: length)
        layoutPages()
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
