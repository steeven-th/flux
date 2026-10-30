import AppKit
import SwiftUI

/// A tab in the page area: its page, the bar above it when there is one, and its DevTools at its
/// right, as one card. The page area holds one, or one per tab of a split.
@MainActor
final class PaneView: NSView {
    let tab: Tab
    /// In a split every pane has a bar, to tell the pages apart and act on each.
    var isInSplit = false {
        didSet { if oldValue != isInSplit { update() } }
    }

    private let state: BrowserState
    private let pageArea = NSView()
    private lazy var header: NSView = {
        let view = NSHostingView(rootView: PaneHeader(state: state, tab: tab))
        view.safeAreaRegions = []
        view.sizingOptions = []
        return view
    }()
    private let responsiveLayout = ResponsiveLayout()
    private lazy var responsiveView: NSView = {
        let view = NSHostingView(rootView: ResponsiveView(state: state, tab: tab, layout: responsiveLayout))
        view.safeAreaRegions = []
        // Its content is empty while the responsive mode is off, and its size would then pull the
        // window down to its smallest.
        view.sizingOptions = []
        return view
    }()
    private let devToolsContainer = NSView()
    /// Fills the point between the page and its DevTools, which are two windows.
    private let devToolsLine = NSBox()
    private let sidePanelContainer = NSView()
    private lazy var sidePanelHeader: NSView = {
        let view = NSHostingView(rootView: SidePanelHeader(state: state, tab: tab))
        view.safeAreaRegions = []
        view.sizingOptions = []
        return view
    }()
    private let sidePanelLine = NSBox()
    private static let sidePanelWidth: CGFloat = 360
    private lazy var devToolsHandle = DevToolsResizeHandle { [weak self] delta in self?.resizeDevTools(by: delta) }
    private var hasHeader = false

    init(tab: Tab, state: BrowserState) {
        self.tab = tab
        self.state = state
        super.init(frame: .zero)
        for line in [devToolsLine, sidePanelLine] {
            line.boxType = .custom
            line.borderWidth = 0
            line.fillColor = NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(white: 0.25, alpha: 1)
                    : NSColor(white: 0.82, alpha: 1)
            }
        }
        for view in [pageArea, responsiveView, sidePanelHeader, sidePanelContainer, sidePanelLine, devToolsContainer, devToolsLine, header] {
            addSubview(view)
        }
        pageArea.addSubview(tab.browserView)
        observe()
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not available")
    }

    private func observe() {
        withObservationTracking {
            _ = state.isDeveloperMode(for: tab.url)
            _ = tab.devTools
            _ = tab.sidePanel
            _ = tab.emulation
            _ = state.responsiveOptions
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.observe()
            }
        }
    }

    private func update() {
        hasHeader = isInSplit || state.isDeveloperMode(for: tab.url)
        header.isHidden = !hasHeader
        let devTools = tab.devTools
        devToolsContainer.subviews.filter { $0 !== devTools }.forEach { $0.removeFromSuperview() }
        if let devTools, devTools.superview !== devToolsContainer {
            devTools.autoresizingMask = [.width, .height]
            devToolsContainer.addSubview(devTools)
        }
        let sidePanel = tab.sidePanel
        sidePanelContainer.subviews.filter { $0 !== sidePanel }.forEach { $0.removeFromSuperview() }
        if let sidePanel, sidePanel.superview !== sidePanelContainer {
            sidePanel.autoresizingMask = [.width, .height]
            sidePanelContainer.addSubview(sidePanel)
        }
        layoutContents()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        layoutContents()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { devToolsHandle.hide() }
    }

    private func layoutContents() {
        let headerHeight = hasHeader ? DeveloperBar.height : 0
        let body = NSRect(x: 0, y: 0, width: bounds.width, height: max(bounds.height - headerHeight, 0))
        header.frame = NSRect(x: 0, y: body.maxY, width: bounds.width, height: headerHeight)
        // The page keeps some room when the pane is narrow.
        let devToolsWidth = tab.devTools == nil ? 0 : max(min(state.devToolsWidth, body.width - 200), min(280, body.width / 2))
        let line: CGFloat = devToolsWidth > 0 ? 1 : 0
        // The page keeps some room for itself too.
        let panelWidth = tab.sidePanel == nil ? 0 : min(Self.sidePanelWidth, max(body.width - devToolsWidth - line - 300, 200))
        let panelLine: CGFloat = panelWidth > 0 ? 1 : 0
        pageArea.frame = NSRect(x: 0, y: 0, width: body.width - devToolsWidth - line - panelWidth - panelLine, height: body.height)
        sidePanelLine.frame = NSRect(x: pageArea.frame.maxX, y: 0, width: panelLine, height: body.height)
        let panelHeaderHeight = min(SidePanelHeader.height, body.height)
        sidePanelHeader.frame = NSRect(x: sidePanelLine.frame.maxX, y: body.height - panelHeaderHeight, width: panelWidth, height: panelHeaderHeight)
        sidePanelContainer.frame = NSRect(x: sidePanelLine.frame.maxX, y: 0, width: panelWidth, height: body.height - panelHeaderHeight)
        for view in [sidePanelHeader, sidePanelContainer, sidePanelLine] {
            view.isHidden = panelWidth == 0
        }
        tab.sidePanel?.frame = sidePanelContainer.bounds
        devToolsLine.frame = NSRect(x: sidePanelContainer.frame.maxX, y: 0, width: line, height: body.height)
        devToolsContainer.frame = NSRect(x: body.width - devToolsWidth, y: 0, width: devToolsWidth, height: body.height)
        devToolsContainer.isHidden = devToolsWidth == 0
        devToolsLine.isHidden = devToolsWidth == 0
        tab.devTools?.frame = devToolsContainer.bounds
        responsiveView.frame = pageArea.frame
        layoutPage()
        roundCorners()
        placeDevToolsHandle()
    }

    /// In responsive mode the page takes the size it is shown at, centered under the device
    /// toolbar and shrunk to fit if needed, as in DevTools' device mode. Not in a split, where
    /// panes are too narrow for it.
    private func layoutPage() {
        let page = tab.browserView
        let bounds = pageArea.bounds
        guard !isInSplit, let emulation = tab.emulation else {
            responsiveView.isHidden = true
            page.autoresizingMask = [.width, .height]
            page.frame = bounds
            return
        }
        responsiveView.isHidden = false
        let options = state.responsiveOptions
        let ruler = options.contains(.rulers) ? ResponsiveView.rulerSize : 0
        let mediaQueries = options.contains(.mediaQueries) ? ResponsiveView.mediaQueriesHeight : 0
        let side = 20 + ruler
        let top = ResponsiveView.toolbarHeight + 12 + ruler + mediaQueries
        let bottom = 12 + ResponsiveView.handleSize
        let room = NSRect(x: side, y: bottom, width: max(bounds.width - side * 2, 50), height: max(bounds.height - top - bottom, 50))
        let fit = min(room.width / CGFloat(emulation.width), room.height / CGFloat(emulation.height))
        // A page larger than the room would spill out of the window, so zooming in stops at the fit.
        let scale = min(emulation.zoom.value.map { CGFloat($0) } ?? 1, fit)
        let size = NSSize(width: (CGFloat(emulation.width) * scale).rounded(), height: (CGFloat(emulation.height) * scale).rounded())
        let frame = NSRect(x: (room.midX - size.width / 2).rounded(), y: room.maxY - size.height, width: size.width, height: size.height)
        page.autoresizingMask = []
        page.frame = frame
        responsiveLayout.pageFrame = CGRect(x: frame.minX, y: bounds.height - frame.maxY, width: frame.width, height: frame.height)
        responsiveLayout.scale = Double(scale)
        tab.applyEmulation(scale: Double(scale))
    }

    /// Only the outer corners of the card are rounded: the page and its DevTools meet the bar and
    /// each other with square ones.
    private func roundCorners() {
        let top: CACornerMask = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        let right: CACornerMask = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        var page: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        var devToolsCorners = right
        if hasHeader {
            page.subtract(top)
            devToolsCorners.subtract(top)
        }
        if tab.devTools != nil || tab.sidePanel != nil { page.subtract(right) }
        // In responsive mode the background around the page takes the page's corners.
        for view in [pageArea, responsiveView] {
            view.wantsLayer = true
            view.layer?.cornerRadius = FLXPageCornerRadius
            // SwiftUI's view is flipped, so its top corners are the ones at min Y.
            view.layer?.maskedCorners = view.isFlipped ? page.flipped : page
            view.layer?.masksToBounds = true
        }
        tab.browserView.roundedCorners = responsiveView.isHidden ? page : []
        tab.devTools?.roundedCorners = devToolsCorners
        // Against the DevTools when they are open, at the card's edge otherwise. Its header takes
        // the top corner.
        let panelCorners = tab.devTools == nil ? devToolsCorners : []
        sidePanelHeader.wantsLayer = true
        sidePanelHeader.layer?.cornerRadius = FLXPageCornerRadius
        sidePanelHeader.layer?.maskedCorners = panelCorners.intersection(top).flipped
        tab.sidePanel?.roundedCorners = panelCorners.subtracting(top)
    }

    /// The handle is a window of its own, over the line between the page and its DevTools, since
    /// both are windows too. Added again each time, so it stays above page windows added since.
    func placeDevToolsHandle() {
        guard let window, !devToolsContainer.isHidden else { return devToolsHandle.hide() }
        let line = devToolsContainer.convert(devToolsContainer.bounds, to: nil)
        let frame = window.convertToScreen(NSRect(x: line.minX - 4, y: line.minY, width: 8, height: line.height))
        devToolsHandle.show(frame: frame, over: window)
    }

    private func resizeDevTools(by delta: CGFloat) {
        state.devToolsWidth = min(max(devToolsContainer.frame.width - delta, 280), bounds.width - 200)
        layoutContents()
    }
}

extension CACornerMask {
    /// The same corners in a flipped view, where min Y is the top.
    var flipped: CACornerMask {
        var mask: CACornerMask = []
        if contains(.layerMinXMinYCorner) { mask.insert(.layerMinXMaxYCorner) }
        if contains(.layerMaxXMinYCorner) { mask.insert(.layerMaxXMaxYCorner) }
        if contains(.layerMinXMaxYCorner) { mask.insert(.layerMinXMinYCorner) }
        if contains(.layerMaxXMaxYCorner) { mask.insert(.layerMaxXMinYCorner) }
        return mask
    }
}
