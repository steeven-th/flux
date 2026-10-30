import Foundation
import Observation

/// Tabs shown side by side. They are the split's children in the sidebar, in pane order.
@MainActor
@Observable
final class Split: NSObject, Identifiable {
    let id: UUID
    let spaceID: UUID
    private(set) var isVertical: Bool

    @ObservationIgnored private(set) var node: SidebarNode

    init(node: SidebarNode) {
        id = node.id
        spaceID = node.spaceID
        isVertical = node.isVertical
        self.node = node
    }

    func setVertical(_ isVertical: Bool) {
        self.isVertical = isVertical
        node.isVertical = isVertical
    }

    func place(section: SidebarNode.Section, parentID: UUID?, position: String) {
        node.section = section
        node.parentID = parentID
        node.position = position
    }
}
