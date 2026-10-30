import AppKit
import GRDB

/// Firefox's profiles and their bookmarks. Firefox keeps bookmarks and history in places.sqlite,
/// and its site icons in favicons.sqlite.
enum FirefoxLibrary {
    static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/Firefox", directoryHint: .isDirectory)

    private struct Profile {
        let name: String
        let path: String
        let folder: URL
    }

    /// profiles.ini lists the profiles. The Install section names the one Firefox opens.
    private static func readProfiles() throws -> (profiles: [Profile], opened: String?) {
        guard let text = try? String(contentsOf: folder.appending(path: "profiles.ini"), encoding: .utf8) else {
            throw ImportError.unreadable
        }
        var sections: [(name: String, values: [String: String])] = []
        for line in text.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if line.hasPrefix("["), line.hasSuffix("]") {
                sections.append((String(line.dropFirst().dropLast()), [:]))
            } else if let equal = line.firstIndex(of: "="), !sections.isEmpty {
                sections[sections.count - 1].values[String(line[..<equal])] = String(line[line.index(after: equal)...])
            }
        }
        let profiles = sections.filter { $0.name.hasPrefix("Profile") }.compactMap { section -> Profile? in
            guard let path = section.values["Path"] else { return nil }
            let folder = section.values["IsRelative"] == "0" ? URL(filePath: path) : folder.appending(path: path, directoryHint: .isDirectory)
            return Profile(name: section.values["Name"] ?? path, path: path, folder: folder)
        }
        let opened = sections.first { $0.name.hasPrefix("Install") }?.values["Default"]
            ?? sections.first { $0.name.hasPrefix("Profile") && $0.values["Default"] == "1" }?.values["Path"]
        return (profiles, opened)
    }

    static var lastSpaceID: String? {
        try? readProfiles().opened
    }

    /// Profiles without bookmarks are left out: Firefox makes some nobody uses.
    static func loadSpaces() throws -> [ImportedSpace] {
        let (profiles, opened) = try readProfiles()
        return profiles.compactMap { profile in
            guard let places = SQLiteCopy(of: profile.folder.appending(path: "places.sqlite")) else { return nil }
            defer { places.close() }
            let favorites = (try? places.database.read { db in try bookmarks(in: db) }) ?? []
            guard !favorites.isEmpty || profile.path == opened else { return nil }
            // Firefox names its profiles like "default-release": the profile Firefox opens is the
            // browser itself.
            let name = profile.path == opened ? "Firefox" : profile.name
            return ImportedSpace(
                id: profile.path, name: name, icon: nil, color: nil, profileFolder: profile.folder,
                pinned: [], favorites: favorites, today: []
            )
        }
    }

    /// The toolbar's bookmarks, then the menu's and the others in folders of their own.
    private static func bookmarks(in db: Database) throws -> [ImportedItem] {
        func root(_ guid: String) throws -> Int64? {
            try Int64.fetchOne(db, sql: "SELECT id FROM moz_bookmarks WHERE guid = ?", arguments: [guid])
        }
        func children(of parent: Int64) throws -> [ImportedItem] {
            let rows = try Row.fetchAll(db, sql: """
                SELECT moz_bookmarks.id, moz_bookmarks.type, moz_bookmarks.title, moz_places.url
                FROM moz_bookmarks LEFT JOIN moz_places ON moz_places.id = moz_bookmarks.fk
                WHERE moz_bookmarks.parent = ? ORDER BY moz_bookmarks.position
                """, arguments: [parent])
            return try rows.compactMap { row in
                let title: String = row["title"] ?? ""
                switch row["type"] as Int? {
                case 1:
                    // Smart bookmarks are queries of Firefox's, "place:" addresses.
                    guard let url: String = row["url"], !url.hasPrefix("place:") else { return nil }
                    return .tab(ImportedTab(title: title, url: url))
                case 2:
                    return .folder(title: title, items: try children(of: row["id"]))
                default:
                    return nil
                }
            }
        }
        var items = try root("toolbar_____").map(children(of:)) ?? []
        for (guid, name) in [("menu________", String(localized: "Bookmarks Menu")), ("unfiled_____", String(localized: "Other Bookmarks"))] {
            if let id = try root(guid) {
                let content = try children(of: id)
                if !content.isEmpty { items.append(.folder(title: name, items: content)) }
            }
        }
        return items
    }
}

/// A copy of a database another app may hold open, with its write-ahead log, read then thrown away.
final class SQLiteCopy {
    let database: DatabaseQueue
    private let folder: URL

    init?(of file: URL) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: file.path) else { return nil }
        folder = manager.temporaryDirectory.appending(path: "Import \(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm", "-journal"] {
                let source = URL(filePath: file.path + suffix)
                if manager.fileExists(atPath: source.path) {
                    try manager.copyItem(at: source, to: folder.appending(path: file.lastPathComponent + suffix))
                }
            }
            database = try DatabaseQueue(path: folder.appending(path: file.lastPathComponent).path)
        } catch {
            try? manager.removeItem(at: folder)
            return nil
        }
    }

    func close() {
        try? FileManager.default.removeItem(at: folder)
    }
}

/// Site icons from favicons.sqlite, so imported tabs show theirs before their page is loaded.
struct FirefoxFavicons: SiteIcons {
    private let copy: SQLiteCopy?

    init(profileFolder: URL) {
        copy = SQLiteCopy(of: profileFolder.appending(path: "favicons.sqlite"))
    }

    func image(for url: String) -> NSImage? {
        guard let copy, let components = URLComponents(string: url), let scheme = components.scheme, let host = components.host else { return nil }
        let sql = """
            SELECT moz_icons.data FROM moz_pages_w_icons
            JOIN moz_icons_to_pages ON moz_icons_to_pages.page_id = moz_pages_w_icons.id
            JOIN moz_icons ON moz_icons.id = moz_icons_to_pages.icon_id
            WHERE moz_pages_w_icons.page_url = ? OR moz_pages_w_icons.page_url LIKE ?
            ORDER BY moz_pages_w_icons.page_url = ? DESC, moz_icons.width DESC LIMIT 1
            """
        let data = try? copy.database.read { db in
            try Data.fetchOne(db, sql: sql, arguments: [url, "\(scheme)://\(host)/%", url])
        }
        return data.flatMap(NSImage.init(data:))
    }

    func close() {
        copy?.close()
    }
}
