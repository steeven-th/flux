import Foundation
import GRDB

/// One entry of a space's sidebar: a tab, a folder, or a split of tabs shown side by side.
struct SidebarNode: Codable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "node"

    enum Kind: String, Codable {
        case tab, folder, split
    }

    enum Section: String, Codable {
        /// Tabs kept as icons at the top of the sidebar.
        case pinned
        /// Kept tabs, which can be grouped in folders.
        case favorites
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
    /// For kept tabs (pinned or favorites), the page they were kept on, which they can go back to.
    var originalURL: String?
    /// For folders.
    var isExpanded: Bool
    var lastActiveAt: Date?
    var createdAt: Date
    /// How far the page at `url` was scrolled, to put it back there when it loads again.
    var scrollY: Double?
    /// For splits, whether their tabs are stacked rather than side by side.
    var isVertical = false
    /// For tabs in a split, their part of its width or height. Nil until the user resizes them.
    var share: Double?
    /// For tabs, the pages before and after `url`.
    var history: NavigationHistory?
}

/// A tab of Today that was closed or left unseen for too long.
struct ArchivedTab: Codable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "archivedTab"

    var id: UUID
    var spaceID: UUID
    var title: String
    var url: String
    var archivedAt: Date
}

/// A file downloaded in the profile. Chromium keeps no list of its own that Flux could read.
struct DownloadRecord: Codable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "download"

    var id: UUID
    var path: String
    var url: String
    var mimeType: String
    var size: Int64
    var finishedAt: Date
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
        migrator.registerMigration("v2 pinned tabs and folders") { db in
            try db.alter(table: "node") { t in
                t.add(column: "pinnedURL", .text)
                t.add(column: "isExpanded", .boolean).notNull().defaults(to: true)
            }
        }
        // The top icons used to be called favorites and the folder tree pinned, after Arc.
        migrator.registerMigration("v3 swap pinned and favorites") { db in
            try db.execute(sql: """
                UPDATE node SET section = CASE section
                    WHEN 'pinned' THEN 'favorites' WHEN 'favorites' THEN 'pinned' ELSE section END
                """)
            try db.alter(table: "node") { t in
                t.rename(column: "pinnedURL", to: "originalURL")
            }
        }
        migrator.registerMigration("v4 archive") { db in
            try db.create(table: "archivedTab") { t in
                t.primaryKey("id", .blob)
                t.column("spaceID", .blob).notNull()
                t.column("title", .text).notNull()
                t.column("url", .text).notNull()
                t.column("archivedAt", .datetime).notNull()
            }
            try db.create(index: "archivedTab_by_space", on: "archivedTab", columns: ["spaceID", "archivedAt"])
        }
        migrator.registerMigration("v5 scroll position") { db in
            try db.alter(table: "node") { t in
                t.add(column: "scrollY", .double)
            }
        }
        migrator.registerMigration("v6 downloads") { db in
            try db.create(table: "download") { t in
                t.primaryKey("id", .blob)
                t.column("path", .text).notNull()
                t.column("url", .text).notNull()
                t.column("mimeType", .text).notNull()
                t.column("size", .integer).notNull()
                t.column("finishedAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v7 split view") { db in
            try db.alter(table: "node") { t in
                t.add(column: "isVertical", .boolean).notNull().defaults(to: false)
                t.add(column: "share", .double)
            }
        }
        migrator.registerMigration("v8 navigation history") { db in
            try db.alter(table: "node") { t in
                t.add(column: "history", .jsonText)
            }
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

    func save(_ nodes: [SidebarNode]) throws {
        try queue.write { db in
            for node in nodes {
                try node.save(db)
            }
        }
    }

    func deleteNodes(in spaceID: UUID) throws {
        _ = try queue.write { db in try SidebarNode.filter(Column("spaceID") == spaceID).deleteAll(db) }
    }

    func delete(nodeID: UUID) throws {
        _ = try queue.write { db in try SidebarNode.deleteOne(db, key: nodeID) }
    }

    func archivedTabs(in spaceID: UUID) throws -> [ArchivedTab] {
        try queue.read { db in
            try ArchivedTab
                .filter(Column("spaceID") == spaceID)
                .order(Column("archivedAt").desc)
                .fetchAll(db)
        }
    }

    func archive(_ tab: ArchivedTab) throws {
        try queue.write { db in try tab.save(db) }
    }

    func deleteArchivedTab(id: UUID) throws {
        _ = try queue.write { db in try ArchivedTab.deleteOne(db, key: id) }
    }

    func clearArchive(in spaceID: UUID) throws {
        _ = try queue.write { db in try ArchivedTab.filter(Column("spaceID") == spaceID).deleteAll(db) }
    }

    func deleteArchivedTabs(before date: Date) throws {
        _ = try queue.write { db in try ArchivedTab.filter(Column("archivedAt") < date).deleteAll(db) }
    }

    func downloads() throws -> [DownloadRecord] {
        try queue.read { db in try DownloadRecord.order(Column("finishedAt").desc).fetchAll(db) }
    }

    func save(_ download: DownloadRecord) throws {
        try queue.write { db in try download.save(db) }
    }

    func deleteDownload(id: UUID) throws {
        _ = try queue.write { db in try DownloadRecord.deleteOne(db, key: id) }
    }
}
