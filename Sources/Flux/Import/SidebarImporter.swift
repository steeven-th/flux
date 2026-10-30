import AppKit

/// Turns another browser's sidebar items into Flux's sidebar nodes, for one space.
@MainActor
struct SidebarImporter {
    let spaceID: UUID
    let favicons: any SiteIcons
    let cache: FaviconCache?
    private(set) var nodes: [SidebarNode] = []

    init(spaceID: UUID, favicons: any SiteIcons, cache: FaviconCache?) {
        self.spaceID = spaceID
        self.favicons = favicons
        self.cache = cache
    }

    /// Adds the items at the end of the section, after the entry at `position`.
    mutating func add(_ items: [ImportedItem], section: SidebarNode.Section, after position: String?) {
        var last = position
        add(items, section: section, parentID: nil, depth: -1, after: &last)
    }

    /// `depth` is -1 at the top of a section, 0 in a top-level folder. Folders deeper than Flux
    /// allows give their content to their parent.
    private mutating func add(_ items: [ImportedItem], section: SidebarNode.Section, parentID: UUID?, depth: Int, after last: inout String?) {
        for item in items {
            switch item {
            case .tab(let tab):
                nodes.append(tabNode(tab, section: section, parentID: parentID, position: next(&last)))
            case .folder(let title, let children):
                // Only favorites have folders: in the grid or Today, their tabs come one after another.
                guard section == .favorites, depth + 1 <= BrowserState.maxFolderDepth else {
                    add(children, section: section, parentID: parentID, depth: depth, after: &last)
                    continue
                }
                let folder = SidebarNode(
                    id: UUID(), spaceID: spaceID, parentID: parentID, kind: .folder, section: section,
                    position: next(&last), title: title, url: nil, originalURL: nil,
                    isExpanded: false, lastActiveAt: nil, createdAt: Date()
                )
                nodes.append(folder)
                var inner: String?
                add(children, section: section, parentID: folder.id, depth: depth + 1, after: &inner)
            case .split(let tabs, let shares, let isVertical):
                guard section != .pinned, tabs.count > 1 else {
                    add(tabs.map(ImportedItem.tab), section: section, parentID: parentID, depth: depth, after: &last)
                    continue
                }
                var split = SidebarNode(
                    id: UUID(), spaceID: spaceID, parentID: parentID, kind: .split, section: section,
                    position: next(&last), title: "", url: nil, originalURL: nil,
                    isExpanded: true, lastActiveAt: Date(), createdAt: Date()
                )
                split.isVertical = isVertical
                nodes.append(split)
                var inner: String?
                for (tab, share) in zip(tabs, shares) {
                    var node = tabNode(tab, section: section, parentID: split.id, position: next(&inner))
                    node.share = share
                    nodes.append(node)
                }
            }
        }
    }

    private func tabNode(_ tab: ImportedTab, section: SidebarNode.Section, parentID: UUID?, position: String) -> SidebarNode {
        if let cache, cache.image(for: tab.url) == nil, let image = favicons.image(for: tab.url) {
            cache.store(image, for: tab.url)
        }
        return SidebarNode(
            id: UUID(), spaceID: spaceID, parentID: parentID, kind: .tab, section: section,
            position: position, title: tab.title, url: tab.url,
            originalURL: section == .today ? nil : tab.url,
            isExpanded: true, lastActiveAt: Date(), createdAt: Date()
        )
    }

    private func next(_ last: inout String?) -> String {
        let position = FractionalIndex.between(last, nil)
        last = position
        return position
    }
}
