import AppKit
import GRDB

/// Favicons from the Favicons database Chromium keeps in each of Arc's profiles, so imported tabs
/// show their icon before their page is loaded. Arc may be running and holding a lock on the file,
/// so a copy is read, journal included.
struct ArcFavicons {
    private let database: DatabaseQueue?
    private let copyFolder: URL

    init(profile: String) {
        let source = ArcLibrary.profileFolder(profile)
        copyFolder = FileManager.default.temporaryDirectory.appending(path: "Arc Favicons \(UUID().uuidString)", directoryHint: .isDirectory)
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: copyFolder, withIntermediateDirectories: true)
            for name in ["Favicons", "Favicons-journal"] where manager.fileExists(atPath: source.appending(path: name).path) {
                try manager.copyItem(at: source.appending(path: name), to: copyFolder.appending(path: name))
            }
            database = try DatabaseQueue(path: copyFolder.appending(path: "Favicons").path)
        } catch {
            database = nil
        }
    }

    /// The largest icon of the page, or else of another page of the same site.
    func image(for url: String) -> NSImage? {
        guard let database, let components = URLComponents(string: url), let scheme = components.scheme, let host = components.host else { return nil }
        let sql = """
            SELECT favicon_bitmaps.image_data FROM icon_mapping
            JOIN favicon_bitmaps ON favicon_bitmaps.icon_id = icon_mapping.icon_id
            WHERE icon_mapping.page_url = ? OR icon_mapping.page_url LIKE ?
            ORDER BY icon_mapping.page_url = ? DESC, favicon_bitmaps.width DESC LIMIT 1
            """
        let data = try? database.read { db in
            try Data.fetchOne(db, sql: sql, arguments: [url, "\(scheme)://\(host)/%", url])
        }
        return data.flatMap(NSImage.init(data:))
    }

    func close() {
        try? FileManager.default.removeItem(at: copyFolder)
    }
}
