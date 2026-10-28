import SwiftUI

struct Space: Identifiable, Hashable {
    let id: UUID
    let name: String
    let color: Color

    // Fixed ids, so each space finds its profile folder again on the next launch.
    static let defaults = [
        Space(id: UUID(uuidString: "6F1C2B7E-3D4A-4C1E-9B2F-1A2B3C4D5E01")!, name: "Personal", color: .orange),
        Space(id: UUID(uuidString: "6F1C2B7E-3D4A-4C1E-9B2F-1A2B3C4D5E02")!, name: "Work", color: .blue),
    ]
}
