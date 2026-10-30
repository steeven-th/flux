import Foundation

/// The profiles of a browser built on Chromium, read from the folder where it keeps them, and
/// their bookmarks.
struct ChromiumProfiles {
    struct Profile {
        let directory: String
        let name: String
        /// "#RRGGBB"
        let color: String?
        let folder: URL
    }

    let root: URL

    private var profileState: [String: Any] {
        guard let data = try? Data(contentsOf: root.appending(path: "Local State")),
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return state["profile"] as? [String: Any] ?? [:]
    }

    var lastUsed: String? {
        profileState["last_used"] as? String
    }

    /// The major version of the browser's Chromium.
    var chromiumVersion: Int? {
        (try? String(contentsOf: root.appending(path: "Last Version"), encoding: .utf8))
            .flatMap { Int($0.split(separator: ".").first ?? "") }
    }

    /// In the browser's order. Throws when the folder can't be read, which macOS may refuse until
    /// the user lets Flux read the other app's data.
    func list() throws -> [Profile] {
        let state = profileState
        guard let info = state["info_cache"] as? [String: [String: Any]] else { throw ImportError.unreadable }
        let order = state["profiles_order"] as? [String] ?? info.keys.sorted()
        return order.compactMap { directory in
            guard let profile = info[directory] else { return nil }
            return Profile(
                directory: directory,
                name: profile["name"] as? String ?? directory,
                color: (profile["profile_color_seed"] as? Int).map(Self.hex),
                folder: root.appending(path: directory, directoryHint: .isDirectory)
            )
        }
    }

    /// The bookmark bar's items, and the others' folder with its name.
    static func bookmarks(in profile: URL) -> (bar: [[String: Any]], other: [String: Any]?) {
        guard let data = try? Data(contentsOf: profile.appending(path: "Bookmarks")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = root["roots"] as? [String: Any] else { return ([], nil) }
        let bar = (roots["bookmark_bar"] as? [String: Any])?["children"] as? [[String: Any]] ?? []
        return (bar, roots["other"] as? [String: Any])
    }

    static func children(of node: [String: Any]) -> [ImportedItem] {
        (node["children"] as? [[String: Any]] ?? []).compactMap(item)
    }

    static func item(_ node: [String: Any]) -> ImportedItem? {
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

/// Chrome, Brave and Edge: a space per profile, its bookmarks as favorites. Their pinned tabs are
/// in the sessions Chromium saves, which don't come.
enum ChromiumBrowserLibrary {
    static func loadSpaces(from profiles: ChromiumProfiles) throws -> [ImportedSpace] {
        try profiles.list().map { profile in
            let bookmarks = ChromiumProfiles.bookmarks(in: profile.folder)
            var favorites = bookmarks.bar.compactMap(ChromiumProfiles.item)
            if let other = bookmarks.other, case .folder(let title, let items) = ChromiumProfiles.item(other), !items.isEmpty {
                favorites.append(.folder(title: title, items: items))
            }
            return ImportedSpace(
                id: profile.directory, name: profile.name, icon: nil, color: profile.color,
                profileFolder: profile.folder, pinned: [], favorites: favorites, today: []
            )
        }
    }
}
