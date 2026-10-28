import Foundation
import GRDB

struct SpaceRecord: Codable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "space"

    var id: UUID
    var name: String
    /// An emoji shown instead of the space's initial.
    var icon: String?
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
        migrator.registerMigration("v2 space icon") { db in
            try db.alter(table: "space") { t in
                t.add(column: "icon", .text)
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

    func delete(_ space: SpaceRecord) throws {
        _ = try queue.write { db in try space.delete(db) }
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

extension AppDatabase {
    private static let pendingDeletionsKey = "profileFoldersToDelete"

    /// Chromium keeps a profile's files open while it runs, so a deleted space's profile folder is
    /// removed at the next launch, before Chromium starts.
    func scheduleDeletion(ofProfileFolder name: String) throws {
        var names = try pendingProfileDeletions()
        names.append(name)
        try setSetting(Self.pendingDeletionsKey, to: String(data: try JSONEncoder().encode(names), encoding: .utf8))
    }

    func deletePendingProfileFolders() throws {
        for name in try pendingProfileDeletions() where !name.isEmpty && !name.contains("/") {
            let folder = AppPaths.profileFolder(named: name)
            if FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.removeItem(at: folder)
            }
        }
        try setSetting(Self.pendingDeletionsKey, to: nil)
    }

    private func pendingProfileDeletions() throws -> [String] {
        guard let json = try setting(Self.pendingDeletionsKey) else { return [] }
        return try JSONDecoder().decode([String].self, from: Data(json.utf8))
    }
}
