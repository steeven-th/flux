import Foundation
import GRDB

/// History from a browser that isn't Chromium, for a new profile. Chromium makes the profile's
/// History database when it first opens the profile and keeps it locked while it runs, so the
/// visits wait in a file of their own and go in at the next launch, before profiles open.
enum PendingHistory {
    private static let fileName = "Flux Pending History.sqlite"
    /// Firefox counts microseconds from 1970, Chromium from 1601.
    private static let chromiumEpochOffset: Int64 = 11_644_473_600 * 1_000_000
    /// Chromium's link transition, starting and ending a redirect chain.
    private static let linkTransition = 0x3000_0000

    /// The latest visits of places.sqlite, kept for `profile`.
    static func stageFirefoxHistory(from firefoxProfile: URL, for profile: URL) {
        guard let places = SQLiteCopy(of: firefoxProfile.appending(path: "places.sqlite")) else { return }
        defer { places.close() }
        let stage = profile.appending(path: fileName)
        try? FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: stage)
        guard let visits = try? places.database.read({ db in
            try Row.fetchAll(db, sql: """
                SELECT moz_places.url, moz_places.title, moz_historyvisits.visit_date
                FROM moz_historyvisits JOIN moz_places ON moz_places.id = moz_historyvisits.place_id
                WHERE moz_places.url LIKE 'http%' ORDER BY moz_historyvisits.visit_date DESC LIMIT 100000
                """)
        }), !visits.isEmpty, let queue = try? DatabaseQueue(path: stage.path) else { return }
        try? queue.write { db in
            try db.execute(sql: "CREATE TABLE visit (url TEXT NOT NULL, title TEXT, time INTEGER NOT NULL)")
            for visit in visits {
                let time: Int64 = visit["visit_date"] ?? 0
                try db.execute(sql: "INSERT INTO visit VALUES (?, ?, ?)", arguments: [visit["url"], visit["title"], time + chromiumEpochOffset])
            }
        }
    }

    /// For every profile with visits waiting, once Chromium has made its History database.
    static func applyAll() {
        let manager = FileManager.default
        guard let profiles = try? manager.contentsOfDirectory(at: AppPaths.chromiumRoot, includingPropertiesForKeys: nil) else { return }
        for profile in profiles {
            let stage = profile.appending(path: fileName)
            let history = profile.appending(path: "History")
            guard manager.fileExists(atPath: stage.path), manager.fileExists(atPath: history.path) else { continue }
            if apply(stage, to: history) { try? manager.removeItem(at: stage) }
        }
    }

    private static func apply(_ stage: URL, to history: URL) -> Bool {
        guard let staged = try? DatabaseQueue(path: stage.path), let database = try? DatabaseQueue(path: history.path),
              let visits = try? staged.read({ db in try Row.fetchAll(db, sql: "SELECT url, title, time FROM visit ORDER BY time") })
        else { return false }
        do {
            try database.write { db in
                var urlIDs: [String: Int64] = [:]
                for visit in visits {
                    let url: String = visit["url"]
                    let time: Int64 = visit["time"]
                    if let id = urlIDs[url] {
                        try db.execute(sql: "UPDATE urls SET visit_count = visit_count + 1, last_visit_time = ? WHERE id = ?", arguments: [time, id])
                    } else if let id = try Int64.fetchOne(db, sql: "SELECT id FROM urls WHERE url = ?", arguments: [url]) {
                        urlIDs[url] = id
                        try db.execute(sql: "UPDATE urls SET visit_count = visit_count + 1, last_visit_time = max(last_visit_time, ?) WHERE id = ?", arguments: [time, id])
                    } else {
                        try insert(into: "urls", values: [
                            "url": url, "title": visit["title"] as String? ?? "", "visit_count": 1, "typed_count": 0,
                            "last_visit_time": time, "hidden": 0,
                        ], db: db)
                        urlIDs[url] = db.lastInsertedRowID
                    }
                    try insert(into: "visits", values: [
                        "url": urlIDs[url]!, "visit_time": time, "from_visit": 0, "transition": linkTransition,
                    ], db: db)
                }
            }
            return true
        } catch {
            return false
        }
    }

    /// Columns Chromium requires that aren't given get 0 or an empty text, so the insert keeps
    /// working as Chromium adds columns.
    private static func insert(into table: String, values: [String: (any DatabaseValueConvertible)?], db: Database) throws {
        var row = values
        for column in try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))") {
            let name: String = column["name"]
            guard row[name] == nil, column["notnull"] as Int == 1, column["dflt_value"] as String? == nil, column["pk"] as Int == 0 else { continue }
            let type: String = column["type"]
            row[name] = type.uppercased().contains("CHAR") || type.uppercased().contains("TEXT") ? "" : 0
        }
        let columns = Array(row.keys)
        let sql = "INSERT INTO \(table) (\(columns.joined(separator: ", "))) VALUES (\(columns.map { _ in "?" }.joined(separator: ", ")))"
        try db.execute(sql: sql, arguments: StatementArguments(columns.map { row[$0]! }))
    }
}
