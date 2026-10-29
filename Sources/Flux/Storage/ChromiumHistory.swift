import Foundation
import GRDB

/// A profile's browsing history, read from the `History` database Chromium keeps in the profile
/// folder. Flux keeps no history of its own, so pages removed in chrome://history are gone from
/// Flux too.
///
/// Chromium holds an exclusive lock on the file while it runs, so Flux reads a copy, made again
/// when the file has changed. The journal is copied with it: if Chromium was writing, opening the
/// copy rolls the unfinished write back.
actor ChromiumHistory {
    struct Page: Sendable, Equatable {
        let url: String
        let title: String
        let visitCount: Int
        let typedCount: Int
        let lastVisit: Date
    }

    /// Chromium writes its changes in batches every few seconds, so copying more often is useless.
    private static let minimumCopyInterval: TimeInterval = 5

    private let source: URL
    private let copyFolder: URL
    private var database: DatabaseQueue?
    private var copiedVersion: Date?
    private var lastCopy: Date?

    init(profileFolder: URL) {
        source = profileFolder.appending(path: "History")
        copyFolder = FileManager.default.temporaryDirectory
            .appending(path: "History \(profileFolder.lastPathComponent)", directoryHint: .isDirectory)
    }

    /// Pages whose address or title contains every word of `text`, best first.
    func search(_ text: String, limit: Int) -> [Page] {
        let words = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        refreshCopy()
        guard let database else { return [] }
        let pages = (try? database.read { db in try Self.candidates(matching: words, in: db) }) ?? []
        let now = Date()
        return pages
            .map { page in (page, Self.score(page, text: words.joined(separator: " "), now: now)) }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    private func refreshCopy() {
        let manager = FileManager.default
        let version = (try? manager.attributesOfItem(atPath: source.path)[.modificationDate]) as? Date
        guard let version, version != copiedVersion else { return }
        if let lastCopy, database != nil, Date().timeIntervalSince(lastCopy) < Self.minimumCopyInterval { return }
        lastCopy = Date()
        database = nil
        do {
            try? manager.removeItem(at: copyFolder)
            try manager.createDirectory(at: copyFolder, withIntermediateDirectories: true)
            let copy = copyFolder.appending(path: "History")
            try manager.copyItem(at: source, to: copy)
            let journal = source.deletingLastPathComponent().appending(path: "History-journal")
            if manager.fileExists(atPath: journal.path) {
                try manager.copyItem(at: journal, to: copyFolder.appending(path: "History-journal"))
            }
            var configuration = Configuration()
            configuration.label = "ChromiumHistory"
            let queue = try DatabaseQueue(path: copy.path, configuration: configuration)
            // Reading once applies a pending rollback and checks the copy is usable.
            _ = try queue.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM urls LIMIT 1") }
            database = queue
            copiedVersion = version
        } catch {
            database = nil
            copiedVersion = nil
        }
    }

    private static func candidates(matching words: [String], in db: Database) throws -> [Page] {
        var sql = """
            SELECT url, title, visit_count, typed_count, last_visit_time FROM urls
            WHERE hidden = 0 AND (url LIKE 'http://%' OR url LIKE 'https://%')
            """
        var arguments: [String] = []
        for word in words {
            sql += " AND (url LIKE ? ESCAPE '\\' OR title LIKE ? ESCAPE '\\')"
            let pattern = "%" + word.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_") + "%"
            arguments += [pattern, pattern]
        }
        sql += " ORDER BY last_visit_time DESC LIMIT 200"
        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments)).map { row in
            Page(
                url: row["url"],
                title: row["title"],
                visitCount: row["visit_count"],
                typedCount: row["typed_count"],
                lastVisit: date(fromChromiumTime: row["last_visit_time"])
            )
        }
    }

    /// Chromium counts microseconds since 1601.
    private static func date(fromChromiumTime time: Int64) -> Date {
        Date(timeIntervalSince1970: Double(time) / 1_000_000 - 11_644_473_600)
    }

    /// Pages visited often, typed in by hand, or visited lately come first, and a page whose site
    /// or title starts with the text comes before the others.
    static func score(_ page: Page, text: String, now: Date) -> Double {
        let frequency = log2(Double(page.visitCount + 2 * page.typedCount) + 1)
        let days = max(now.timeIntervalSince(page.lastVisit) / 86_400, 0)
        let recency = 1 / (1 + days / 7)
        var score = frequency * recency
        if startsMatch(page, text: text) { score += 10 }
        return score
    }

    static func startsMatch(_ page: Page, text: String) -> Bool {
        let host = (URL(string: page.url)?.host() ?? "").replacingOccurrences(of: "www.", with: "")
        return host.range(of: text, options: [.anchored, .caseInsensitive]) != nil
            || page.title.range(of: text, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
    }
}
