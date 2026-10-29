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

    @ObservationIgnored private(set) var node: SidebarNode

    init(node: SidebarNode) {
        id = node.id
        spaceID = node.spaceID
        title = node.title
        self.node = node
    }

    func rename(_ title: String) {
        self.title = title
        node.title = title
    }

    func setExpanded(_ isExpanded: Bool) {
        node.isExpanded = isExpanded
    }

    func place(parentID: UUID?, position: String) {
        node.parentID = parentID
        node.position = position
    }
}
