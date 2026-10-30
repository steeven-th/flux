import AppKit
import Observation

@MainActor
@Observable
final class Tab: NSObject, Identifiable {
    let id: UUID
    let spaceID: UUID
    private(set) var url: String
    private(set) var title: String
    private(set) var favicon: NSImage?
    private(set) var isLoaded = false
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    /// The page's DevTools while open, shown next to it.
    private(set) var devTools: FLXBrowserView?

    /// The stored form of the tab, kept in step with the properties above.
    @ObservationIgnored private(set) var node: SidebarNode
    /// Called after the URL or title changed, to save the tab.
    @ObservationIgnored var onChange: ((Tab) -> Void)?
    /// Called when the page opens a link in a new tab or window, with the new page.
    @ObservationIgnored var onOpenPage: ((Tab, FLXBrowserView, FLXOpenDisposition) -> Void)?
    @ObservationIgnored private let profile: FLXProfile
    @ObservationIgnored private let favicons: FaviconCache
    @ObservationIgnored private var loadedView: FLXBrowserView?
    /// Where the page was scrolled before Flux quit or the tab was unloaded, until it has loaded.
    @ObservationIgnored private var scrollToRestore: Double?
    @ObservationIgnored private var pendingDevToolsScript: String?

    /// `page` is a page already created, opened by another tab.
    init(node: SidebarNode, profile: FLXProfile, favicons: FaviconCache, page: FLXBrowserView? = nil) {
        id = node.id
        spaceID = node.spaceID
        url = node.url ?? ""
        title = node.title
        self.node = node
        self.profile = profile
        self.favicons = favicons
        favicon = favicons.image(for: node.url ?? "")
        super.init()
        if let page {
            page.delegate = self
            loadedView = page
            isLoaded = true
        }
    }

    /// Created on first use, so tabs restored at launch don't load their page until shown.
    var browserView: FLXBrowserView {
        if let loadedView {
            return loadedView
        }
        let view = FLXBrowserView(url: url, profile: profile)
        view.delegate = self
        scrollToRestore = node.scrollY
        loadedView = view
        isLoaded = true
        return view
    }

    var displayTitle: String {
        title.isEmpty ? url : title
    }

    var isPinned: Bool {
        node.section == .pinned
    }

    /// Pinned tabs and favorites stay in the sidebar until removed. Today's tabs go when closed.
    var isKept: Bool {
        node.section != .today
    }

    /// True for a kept tab that has navigated away from the page it was kept on.
    var hasLeftOriginalURL: Bool {
        guard isKept, let originalURL = node.originalURL else { return false }
        return originalURL != url
    }

    func load(_ url: String) {
        browserView.loadURL(url)
        update(url: url)
    }

    /// Shows a tool of the page's DevTools, opening them on it if they are closed. DevTools are
    /// driven through InspectorFrontendAPI, the interface Chrome itself uses to drive them.
    func show(_ tool: DevTool) {
        let script = tool == .picker
            ? "InspectorFrontendAPI.showPanel('elements'); InspectorFrontendAPI.enterInspectElementMode(); true"
            : "InspectorFrontendAPI.showPanel('\(tool.panel)'); true"
        if let devTools {
            devTools.evaluateJavaScript(script) { _ in }
        } else {
            pendingDevToolsScript = tool == .picker ? script : nil
            browserView.showDevTools(onPanel: tool.panel)
        }
    }

    /// The frontend takes a moment to load after DevTools open, so the script is tried until it runs.
    private func runPendingDevToolsScript(on devTools: FLXBrowserView, attempts: Int = 20) {
        guard let script = pendingDevToolsScript, attempts > 0 else { return }
        devTools.evaluateJavaScript("typeof InspectorFrontendAPI === 'undefined' ? false : (\(script))") { [weak self] value in
            if value as? Bool == true {
                self?.pendingDevToolsScript = nil
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self?.runPendingDevToolsScript(on: devTools, attempts: attempts - 1)
                }
            }
        }
    }

    /// Only this site's cookies, then the page loads again without them.
    func clearCookiesAndReload() {
        guard let url = URL(string: url), let scheme = url.scheme, let host = url.host() else { return }
        let origin = url.port.map { "\(scheme)://\(host):\($0)" } ?? "\(scheme)://\(host)"
        let page = browserView
        page.sendDevToolsMethod("Storage.clearDataForOrigin", params: ["origin": origin, "storageTypes": "cookies"]) { _ in
            page.reload()
        }
    }

    func goBackToOriginalURL() {
        guard let originalURL = node.originalURL else { return }
        load(originalURL)
    }

    func markActive() {
        node.lastActiveAt = Date()
        onChange?(self)
    }

    func place(section: SidebarNode.Section, parentID: UUID?, position: String) {
        if section == .today {
            node.originalURL = nil
            // Counts as seen now, or a tab kept long ago would be archived right away.
            if node.section != .today { node.lastActiveAt = Date() }
        } else if node.section == .today {
            node.originalURL = url
        }
        node.section = section
        node.parentID = parentID
        node.position = position
    }

    /// Frees the page's memory. The tab stays and loads again when shown, where it was scrolled.
    func unload() {
        guard let view = loadedView else { return }
        loadedView = nil
        isLoaded = false
        saveScrollPosition(of: view) { view.close() }
    }

    func saveScrollPosition(completion: @escaping () -> Void = {}) {
        guard let loadedView else { return completion() }
        saveScrollPosition(of: loadedView, completion: completion)
    }

    private func saveScrollPosition(of view: FLXBrowserView, completion: @escaping () -> Void) {
        let url = url
        view.evaluateJavaScript("window.scrollY") { [weak self] value in
            if let self, self.url == url, let y = value as? Double {
                self.node.scrollY = y > 0 ? y : nil
                self.onChange?(self)
            }
            completion()
        }
    }

    func close() {
        loadedView?.close()
    }

    private func update(url: String? = nil, title: String? = nil) {
        if let url {
            if url != node.url { node.scrollY = nil }
            self.url = url
            node.url = url
            favicon = favicons.image(for: url) ?? favicon
        }
        if let title {
            self.title = title
            node.title = title
        }
        onChange?(self)
    }
}

extension Tab: FLXBrowserViewDelegate {
    func browserView(_ browserView: FLXBrowserView, didChangeURL url: String) {
        update(url: url)
    }

    func browserView(_ browserView: FLXBrowserView, didChangeTitle title: String) {
        update(title: title)
    }

    func browserView(_ browserView: FLXBrowserView, didOpenPage page: FLXBrowserView, disposition: FLXOpenDisposition) {
        onOpenPage?(self, page, disposition)
    }

    func browserView(_ browserView: FLXBrowserView, didOpenDevTools devTools: FLXBrowserView) {
        self.devTools = devTools
        runPendingDevToolsScript(on: devTools)
    }

    func browserViewDidCloseDevTools(_ browserView: FLXBrowserView) {
        devTools = nil
    }

    func browserViewDidChangeNavigationState(_ browserView: FLXBrowserView) {
        canGoBack = browserView.canGoBack
        canGoForward = browserView.canGoForward
    }

    func browserViewDidFinishLoading(_ browserView: FLXBrowserView) {
        guard let y = scrollToRestore else { return }
        scrollToRestore = nil
        browserView.evaluateJavaScript("window.scrollTo(0, \(y))") { _ in }
    }

    func browserView(_ browserView: FLXBrowserView, didChangeFavicon favicon: NSImage) {
        self.favicon = favicon
        favicons.store(favicon, for: url)
    }
}
