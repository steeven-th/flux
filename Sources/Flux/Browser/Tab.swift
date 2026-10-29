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

    /// The stored form of the tab, kept in step with the properties above.
    @ObservationIgnored private(set) var node: SidebarNode
    /// Called after the URL or title changed, to save the tab.
    @ObservationIgnored var onChange: ((Tab) -> Void)?
    /// Called when the page opens a link in a new tab or window, with the new page.
    @ObservationIgnored var onOpenPage: ((Tab, FLXBrowserView, FLXOpenDisposition) -> Void)?
    @ObservationIgnored private let profile: FLXProfile
    @ObservationIgnored private let favicons: FaviconCache
    @ObservationIgnored private var loadedView: FLXBrowserView?

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

    /// Frees the page's memory. The tab stays and loads again when shown.
    func unload() {
        loadedView?.close()
        loadedView = nil
        isLoaded = false
    }

    func close() {
        loadedView?.close()
    }

    private func update(url: String? = nil, title: String? = nil) {
        if let url {
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

    func browserView(_ browserView: FLXBrowserView, didChangeFavicon favicon: NSImage) {
        self.favicon = favicon
        favicons.store(favicon, for: url)
    }
}
