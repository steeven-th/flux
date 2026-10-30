import Foundation

/// A space of another browser, as Flux imports it: its sidebar, and the Chromium profile its
/// history, passwords, sign-ins and extensions come from.
struct ImportedSpace: Identifiable {
    let id: String
    let name: String
    let icon: String?
    /// "#RRGGBB", when the browser has one.
    let color: String?
    let profileFolder: URL
    /// For Flux's grid of pinned tabs: Arc's favorites, the icons at the top of its sidebar.
    let pinned: [ImportedItem]
    /// For Flux's favorites, with their folders: Arc's pinned tabs, Dia's bookmarks.
    let favorites: [ImportedItem]
    let today: [ImportedItem]

    var tabCount: Int {
        (pinned + favorites).reduce(0) { $0 + $1.tabs.count }
    }
}

struct ImportedTab {
    let title: String
    let url: String
}

indirect enum ImportedItem {
    case tab(ImportedTab)
    case folder(title: String, items: [ImportedItem])
    /// `shares` are the parts of the width the browser kept, nil for equal ones.
    case split(tabs: [ImportedTab], shares: [Double?], isVertical: Bool)

    /// Every tab, folders and splits opened up.
    var tabs: [ImportedTab] {
        switch self {
        case .tab(let tab): [tab]
        case .folder(_, let items): items.flatMap(\.tabs)
        case .split(let tabs, _, _): tabs
        }
    }
}
