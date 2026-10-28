import AppKit
import Observation

@MainActor
@Observable
final class Tab: NSObject, Identifiable {
    let id: UUID
    let spaceID: UUID
    private(set) var url: String
    private(set) var title: String

    /// The stored form of the tab, kept in step with `url` and `title`.
    @ObservationIgnored private(set) var node: SidebarNode
    /// Called after the URL or title changed, to save the tab.
    @ObservationIgnored var onChange: ((Tab) -> Void)?
    @ObservationIgnored private let profile: FLXProfile
    @ObservationIgnored private var loadedView: FLXBrowserView?

    init(node: SidebarNode, profile: FLXProfile) {
        id = node.id
        spaceID = node.spaceID
        url = node.url ?? ""
        title = node.title
        self.node = node
        self.profile = profile
    }

    /// Created on first use, so tabs restored at launch don't load their page until shown.
    var browserView: FLXBrowserView {
        if let loadedView {
            return loadedView
        }
        let view = FLXBrowserView(url: url, profile: profile)
        view.delegate = self
        loadedView = view
        return view
    }

    var displayTitle: String {
        title.isEmpty ? url : title
    }

    func load(_ url: String) {
        browserView.loadURL(url)
        update(url: url)
    }

    func markActive() {
        node.lastActiveAt = Date()
        onChange?(self)
    }

    func close() {
        loadedView?.close()
    }

    private func update(url: String? = nil, title: String? = nil) {
        if let url {
            self.url = url
            node.url = url
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
}
