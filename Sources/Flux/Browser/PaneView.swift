import AppKit
import SwiftUI

/// A tab in the page area: its page, the bar above it when there is one, and its DevTools around
/// it, as one card. The page area holds one, or one per tab of a split.
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
    private let sidePanelContainer = NSView()
    private lazy var sidePanelHeader: NSView = {
        let view = NSHostingView(rootView: SidePanelHeader(state: state, tab: tab))
        view.safeAreaRegions = []
        view.sizingOptions = []
        return view
    }()
    private let sidePanelLine = NSBox()
    private static let sidePanelWidth: CGFloat = 360
    private lazy var findBar = FindBarWindow(finder: tab.finder)
    private var hasHeader = false

    init(tab: Tab, state: BrowserState) {
        self.tab = tab
        self.state = state
        super.init(frame: .zero)
        sidePanelLine.boxType = .custom
        sidePanelLine.borderWidth = 0
        sidePanelLine.fillColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.25, alpha: 1)
                : NSColor(white: 0.82, alpha: 1)
        }
        for view in [pageArea, sidePanelHeader, sidePanelContainer, sidePanelLine, header] {
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
            _ = tab.devToolsPageFrame
            _ = tab.sidePanel
            _ = tab.finder.isShown
            _ = tab.finder.focusRequest
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
        // Under the page, which DevTools leave a hole for.
        let devTools = tab.devTools?.view
        pageArea.subviews.filter { $0 !== devTools && $0 !== tab.browserView }.forEach { $0.removeFromSuperview() }
        if let devTools, devTools.superview !== pageArea {
            devTools.autoresizingMask = [.width, .height]
            pageArea.addSubview(devTools, positioned: .below, relativeTo: tab.browserView)
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
        guard newWindow == nil else { return }
        findBar.hide()
    }

    private func layoutContents() {
        let headerHeight = hasHeader ? DeveloperBar.height : 0
        let body = NSRect(x: 0, y: 0, width: bounds.width, height: max(bounds.height - headerHeight, 0))
        header.frame = NSRect(x: 0, y: body.maxY, width: bounds.width, height: headerHeight)
        // The page keeps some room for itself.
        let panelWidth = tab.sidePanel == nil ? 0 : min(Self.sidePanelWidth, max(body.width - 300, 200))
        let panelLine: CGFloat = panelWidth > 0 ? 1 : 0
        pageArea.frame = NSRect(x: 0, y: 0, width: body.width - panelWidth - panelLine, height: body.height)
        sidePanelLine.frame = NSRect(x: pageArea.frame.maxX, y: 0, width: panelLine, height: body.height)
        let panelHeaderHeight = min(SidePanelHeader.height, body.height)
        sidePanelHeader.frame = NSRect(x: sidePanelLine.frame.maxX, y: body.height - panelHeaderHeight, width: panelWidth, height: panelHeaderHeight)
        sidePanelContainer.frame = NSRect(x: sidePanelLine.frame.maxX, y: 0, width: panelWidth, height: body.height - panelHeaderHeight)
        for view in [sidePanelHeader, sidePanelContainer, sidePanelLine] {
            view.isHidden = panelWidth == 0
        }
        tab.sidePanel?.frame = sidePanelContainer.bounds
        tab.devTools?.view.frame = pageArea.bounds
        layoutPage()
        roundCorners()
        placeWindowsOverPage()
    }

    /// DevTools leave room for the page among their panels.
    private func layoutPage() {
        let page = tab.browserView
        let bounds = pageArea.bounds
        let frame = tab.devToolsPageFrame
        guard tab.devTools != nil, !frame.isEmpty else {
            page.autoresizingMask = [.width, .height]
            page.frame = bounds
            return
        }
        page.autoresizingMask = []
        page.frame = NSRect(x: frame.minX, y: bounds.height - frame.maxY, width: frame.width, height: frame.height)
    }

    /// Only the outer corners of the card are rounded: the page and its side panel meet the bar and
    /// each other with square ones.
    private func roundCorners() {
        let top: CACornerMask = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        let right: CACornerMask = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        var page: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        var panelCorners = right
        if hasHeader {
            page.subtract(top)
            panelCorners.subtract(top)
        }
        if tab.sidePanel != nil { page.subtract(right) }
        pageArea.wantsLayer = true
        pageArea.layer?.cornerRadius = FLXPageCornerRadius
        pageArea.layer?.maskedCorners = page
        pageArea.layer?.masksToBounds = true
        // Inside DevTools the page area's own corners round the card.
        tab.browserView.roundedCorners = tab.devTools == nil ? page : []
        // Its header takes the top corner.
        sidePanelHeader.wantsLayer = true
        sidePanelHeader.layer?.cornerRadius = FLXPageCornerRadius
        sidePanelHeader.layer?.maskedCorners = panelCorners.intersection(top).flipped
        tab.sidePanel?.roundedCorners = panelCorners.subtracting(top)
    }

    /// The find bar is a window of its own, over the page windows. Added again each time, so it
    /// stays above page windows added since.
    func placeWindowsOverPage() {
        guard let window, tab.finder.isShown else { return findBar.hide() }
        findBar.show(atTopRightOf: window.convertToScreen(pageArea.convert(pageArea.bounds, to: nil)), over: window)
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
