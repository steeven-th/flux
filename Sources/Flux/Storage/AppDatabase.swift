import Foundation
import GRDB

struct SpaceRecord: Codable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "space"

    var id: UUID
    var name: String
    /// Hex color, "#RRGGBB".
    var color: String
    var position: String
    /// Name of the Chromium profile folder, inside the Chromium root folder. Several spaces can
    /// share one.
    var profileFolder: String
    var selectedTabID: UUID?
    var createdAt: Date
}

/// Data shared by all spaces: the spaces themselves and app-wide state.
final class AppDatabase: Sendable {
    private let queue: DatabaseQueue

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        queue = try DatabaseQueue(path: url.path)
        try Self.migrator.migrate(queue)
    }

    private static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "space") { t in
                t.primaryKey("id", .blob)
                t.column("name", .text).notNull()
                t.column("color", .text).notNull()
                t.column("position", .text).notNull()
                t.column("profileFolder", .text).notNull()
                t.column("selectedTabID", .blob)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "setting") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
        }
        return migrator
    }()

    func spaces() throws -> [SpaceRecord] {
        try queue.read { db in
            try SpaceRecord.order(Column("position")).fetchAll(db)
        }
    }

    func save(_ space: SpaceRecord) throws {
        try queue.write { db in try space.save(db) }
    }

    func setting(_ key: String) throws -> String? {
        try queue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [key])
        }
    }

    func setSetting(_ key: String, to value: String?) throws {
        try queue.write { db in
            if let value {
                try db.execute(sql: "INSERT OR REPLACE INTO setting (key, value) VALUES (?, ?)", arguments: [key, value])
            } else {
                try db.execute(sql: "DELETE FROM setting WHERE key = ?", arguments: [key])
            }
        }
    }
}
