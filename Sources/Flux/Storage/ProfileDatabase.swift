import Foundation
import GRDB

/// One entry of a space's sidebar: a tab or a folder.
struct SidebarNode: Codable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "node"

    enum Kind: String, Codable {
        case tab, folder
    }

    enum Section: String, Codable {
        /// Icons at the top of the sidebar.
        case favorites
        /// Kept tabs, which can be grouped in folders.
        case pinned
        /// Tabs opened today.
        case today
    }

    var id: UUID
    var spaceID: UUID
    var parentID: UUID?
    var kind: Kind
    var section: Section
    var position: String
    var title: String
    var url: String?
    var lastActiveAt: Date?
    var createdAt: Date
}

/// Data Flux keeps for one Chromium profile, stored inside the profile's folder so that deleting
/// the profile deletes it too.
final class ProfileDatabase: Sendable {
    private let queue: DatabaseQueue

    init(profileFolder: URL) throws {
        try FileManager.default.createDirectory(at: profileFolder, withIntermediateDirectories: true)
        queue = try DatabaseQueue(path: profileFolder.appending(path: "Flux.sqlite").path)
        try Self.migrator.migrate(queue)
    }

    private static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "node") { t in
                t.primaryKey("id", .blob)
                t.column("spaceID", .blob).notNull()
                t.column("parentID", .blob).references("node", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("section", .text).notNull()
                t.column("position", .text).notNull()
                t.column("title", .text).notNull()
                t.column("url", .text)
                t.column("lastActiveAt", .datetime)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "node_by_place", on: "node", columns: ["spaceID", "section", "parentID", "position"])
        }
        return migrator
    }()

    func nodes(in spaceID: UUID) throws -> [SidebarNode] {
        try queue.read { db in
            try SidebarNode
                .filter(Column("spaceID") == spaceID)
                .order(Column("position"))
                .fetchAll(db)
        }
    }

    func save(_ node: SidebarNode) throws {
        try queue.write { db in try node.save(db) }
    }

    func deleteNodes(in spaceID: UUID) throws {
        _ = try queue.write { db in try SidebarNode.filter(Column("spaceID") == spaceID).deleteAll(db) }
    }

    func delete(nodeID: UUID) throws {
        _ = try queue.write { db in try SidebarNode.deleteOne(db, key: nodeID) }
    }
}
