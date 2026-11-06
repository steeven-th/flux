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
        var seen = Set<String>()
        return pages
            .map { page in (page, Self.score(page, text: words.joined(separator: " "), now: now)) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
            .filter { seen.insert(Self.pageKey($0.url)).inserted }
            .prefix(limit)
            .map { $0 }
    }

    /// The home page of the most visited site whose domain starts with `text`, as if the domain had
    /// been typed in full. Its title is the home page's, when it was visited.
    func site(startingWith text: String) -> Page? {
        var prefix = text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        for scheme in ["https://", "http://"] where prefix.hasPrefix(scheme) { prefix.removeFirst(scheme.count) }
        if prefix.hasPrefix("www.") { prefix.removeFirst(4) }
        if prefix.hasSuffix("/") { prefix.removeLast() }
        guard prefix.count >= 2, !prefix.contains(where: { $0.isWhitespace || $0 == "/" }) else { return nil }
        refreshCopy()
        guard let database else { return nil }
        let pages = (try? database.read { db in try Self.candidates(onSitesStartingWith: prefix, in: db) }) ?? []
        let sites = Dictionary(grouping: pages) { URL(string: $0.url)?.host() ?? "" }
        guard let (host, visits) = sites.max(by: { Self.weight($0.value) < Self.weight($1.value) }),
              Self.weight(visits) >= 2,
              let scheme = visits.first.flatMap({ URL(string: $0.url)?.scheme })
        else { return nil }
        let home = visits.first { page in
            guard let url = URL(string: page.url) else { return false }
            return (url.path() == "/" || url.path().isEmpty) && url.query() == nil
        }
        return Page(
            url: home?.url ?? "\(scheme)://\(host)/",
            title: home?.title ?? "",
            visitCount: visits.map(\.visitCount).reduce(0, +),
            typedCount: visits.map(\.typedCount).reduce(0, +),
            lastVisit: visits.map(\.lastVisit).max() ?? .distantPast
        )
    }

    private static func weight(_ pages: [Page]) -> Int {
        pages.map { $0.visitCount + 2 * $0.typedCount }.reduce(0, +)
    }

    static func site(of url: String) -> String {
        let host = URL(string: url)?.host() ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The domain and path, shorter to read than the address.
    static func shortAddress(of url: String) -> String {
        guard let address = URL(string: url) else { return url }
        let path = address.path()
        return site(of: url) + (path == "/" ? "" : path)
    }

    /// Addresses that only differ by their fragment or by tracking parameters are the same page.
    static func pageKey(_ url: String) -> String {
        guard var components = URLComponents(string: url) else { return url }
        components.fragment = nil
        components.queryItems = components.queryItems?.filter { item in
            !item.name.hasPrefix("utm_") && !["fbclid", "gclid", "msclkid"].contains(item.name)
        }
        if components.queryItems?.isEmpty == true { components.queryItems = nil }
        return components.string ?? url
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

    private static func candidates(onSitesStartingWith prefix: String, in db: Database) throws -> [Page] {
        let pattern = escapedForLike(prefix) + "%"
        let sql = """
            SELECT url, title, visit_count, typed_count, last_visit_time FROM urls
            WHERE hidden = 0 AND (url LIKE 'https://' || ? ESCAPE '\\' OR url LIKE 'http://' || ? ESCAPE '\\'
                OR url LIKE 'https://www.' || ? ESCAPE '\\' OR url LIKE 'http://www.' || ? ESCAPE '\\')
            ORDER BY visit_count DESC LIMIT 500
            """
        return try Row.fetchAll(db, sql: sql, arguments: [pattern, pattern, pattern, pattern]).map(page)
            // The text has to stay within the domain, not run on into the path.
            .filter { page in
                site(of: page.url).hasPrefix(prefix)
            }
    }

    private static func escapedForLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private static func page(_ row: Row) -> Page {
        Page(
            url: row["url"],
            title: row["title"],
            visitCount: row["visit_count"],
            typedCount: row["typed_count"],
            lastVisit: date(fromChromiumTime: row["last_visit_time"])
        )
    }

    private static func candidates(matching words: [String], in db: Database) throws -> [Page] {
        var sql = """
            SELECT url, title, visit_count, typed_count, last_visit_time FROM urls
            WHERE hidden = 0 AND (url LIKE 'http://%' OR url LIKE 'https://%')
            """
        var arguments: [String] = []
        for word in words {
            sql += " AND (url LIKE ? ESCAPE '\\' OR title LIKE ? ESCAPE '\\')"
            let pattern = "%" + escapedForLike(word) + "%"
            arguments += [pattern, pattern]
        }
        sql += " ORDER BY last_visit_time DESC LIMIT 200"
        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments)).map(page)
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
