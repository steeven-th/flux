import Foundation
import Observation

/// A folder of pinned tabs. Folders can hold other folders.
@MainActor
@Observable
final class Folder: NSObject, Identifiable {
    let id: UUID
    let spaceID: UUID
    private(set) var title: String
    var isEditingTitle = false
    private(set) var isExpanded: Bool
    private(set) var liveSource: LiveSource?
    var isRefreshing = false
    /// Why the last update failed, until one works.
    var refreshError: String?

    @ObservationIgnored private(set) var node: SidebarNode

    init(node: SidebarNode) {
        id = node.id
        spaceID = node.spaceID
        title = node.title
        isExpanded = node.isExpanded
        liveSource = node.liveSource
        self.node = node
    }

    func rename(_ title: String) {
        self.title = title
        node.title = title
    }

    func setExpanded(_ isExpanded: Bool) {
        self.isExpanded = isExpanded
        node.isExpanded = isExpanded
    }

    func setLiveSource(_ source: LiveSource?) {
        liveSource = source
        node.liveSource = source
    }

    func place(parentID: UUID?, position: String) {
        node.parentID = parentID
        node.position = position
    }
}
