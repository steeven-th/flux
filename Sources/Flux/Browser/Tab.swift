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
    @ObservationIgnored private let profile: FLXProfile
    @ObservationIgnored private let favicons: FaviconCache
    @ObservationIgnored private var loadedView: FLXBrowserView?

    init(node: SidebarNode, profile: FLXProfile, favicons: FaviconCache) {
        id = node.id
        spaceID = node.spaceID
        url = node.url ?? ""
        title = node.title
        self.node = node
        self.profile = profile
        self.favicons = favicons
        favicon = favicons.image(for: node.url ?? "")
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

    /// True for a pinned tab that has navigated away from the page it was pinned on.
    var hasLeftPinnedURL: Bool {
        guard isPinned, let pinnedURL = node.pinnedURL else { return false }
        return pinnedURL != url
    }

    func load(_ url: String) {
        browserView.loadURL(url)
        update(url: url)
    }

    func goBackToPinnedURL() {
        guard let pinnedURL = node.pinnedURL else { return }
        load(pinnedURL)
    }

    func markActive() {
        node.lastActiveAt = Date()
        onChange?(self)
    }

    func place(section: SidebarNode.Section, parentID: UUID?, position: String) {
        if section == .pinned, node.section != .pinned {
            node.pinnedURL = url
        } else if section != .pinned {
            node.pinnedURL = nil
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

    func browserView(_ browserView: FLXBrowserView, didChangeFavicon favicon: NSImage) {
        self.favicon = favicon
        favicons.store(favicon, for: url)
    }
}
