import Foundation

/// Dia's profiles and their pinned tabs. Dia keeps its tabs in databases of its own that are
/// encrypted, but its pinned tabs are Chromium bookmarks: a "Favorites" folder for the icons, and
/// a folder per space Dia brought from Arc.
enum DiaLibrary {
    static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/Dia", directoryHint: .isDirectory)

    private static var userData: URL {
        folder.appending(path: "User Data", directoryHint: .isDirectory)
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: userData.appending(path: "Local State").path)
    }

    private static var profiles: [String: Any] {
        guard let data = try? Data(contentsOf: userData.appending(path: "Local State")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return root["profile"] as? [String: Any] ?? [:]
    }

    static var lastSpaceID: String? {
        profiles["last_used"] as? String
    }

    static func loadSpaces() throws -> [ImportedSpace] {
        let profiles = profiles
        guard let info = profiles["info_cache"] as? [String: [String: Any]] else { throw ImportError.unreadable }
        let order = profiles["profiles_order"] as? [String] ?? info.keys.sorted()
        return order.compactMap { directory in
            guard let profile = info[directory] else { return nil }
            let folder = userData.appending(path: directory, directoryHint: .isDirectory)
            let bar = bookmarkBar(in: folder)
            let favorites = bar.filter { !isFavoritesFolder($0) }
            let spaceFolders = favorites.filter { $0["type"] as? String == "folder" }
            // A single space's folder is the space itself: its content comes up a level.
            let content = spaceFolders.count == 1 && favorites.count == 1
                ? children(of: spaceFolders[0])
                : favorites.compactMap(item)
            var name = profile["name"] as? String ?? "Dia"
            // Chromium names a profile nobody named after itself.
            if name.contains("Chromium") {
                name = spaceFolders.count == 1 ? spaceFolders[0]["name"] as? String ?? "Dia" : "Dia"
            }
            return ImportedSpace(
                id: directory,
                name: name,
                icon: nil,
                color: (profile["profile_color_seed"] as? Int).map(hex),
                profileFolder: folder,
                pinned: bar.first(where: isFavoritesFolder).map(children(of:)) ?? [],
                favorites: content,
                today: []
            )
        }
    }

    private static func bookmarkBar(in profile: URL) -> [[String: Any]] {
        guard let data = try? Data(contentsOf: profile.appending(path: "Bookmarks")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bar = (root["roots"] as? [String: Any])?["bookmark_bar"] as? [String: Any] else { return [] }
        return bar["children"] as? [[String: Any]] ?? []
    }

    private static func isFavoritesFolder(_ node: [String: Any]) -> Bool {
        node["type"] as? String == "folder" && node["name"] as? String == "Favorites"
    }

    private static func children(of node: [String: Any]) -> [ImportedItem] {
        (node["children"] as? [[String: Any]] ?? []).compactMap(item)
    }

    private static func item(_ node: [String: Any]) -> ImportedItem? {
        switch node["type"] as? String {
        case "url":
            guard let url = node["url"] as? String, !url.isEmpty else { return nil }
            return .tab(ImportedTab(title: node["name"] as? String ?? "", url: url))
        case "folder":
            return .folder(title: node["name"] as? String ?? String(localized: "Folder"), items: children(of: node))
        default:
            return nil
        }
    }

    /// Chromium keeps colors as signed ARGB integers.
    private static func hex(_ argb: Int) -> String {
        let value = UInt32(truncatingIfNeeded: argb)
        return String(format: "#%02X%02X%02X", (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
    }
}
