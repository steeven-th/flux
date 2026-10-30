import Foundation

/// Arc's spaces and sidebar, read from its own files, which are left as they are. Arc keeps them
/// in StorableSidebar.json: flat lists where an id is followed by its object, items linked by
/// their parent and children ids.
enum ArcLibrary {
    static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/Arc", directoryHint: .isDirectory)

    private static var sidebarFile: URL {
        folder.appending(path: "StorableSidebar.json")
    }

    /// The space Arc showed last, kept in StorableWindows.json.
    static var lastSpaceID: String? {
        guard let data = try? Data(contentsOf: folder.appending(path: "StorableWindows.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return root["lastFocusedSpaceID"] as? String
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: sidebarFile.path)
    }

    /// A profile's folder, where Chromium keeps its history and favicons.
    static func profileFolder(_ profile: String) -> URL {
        folder.appending(path: "User Data/\(profile)", directoryHint: .isDirectory)
    }

    static func loadSpaces() throws -> [ImportedSpace] {
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: sidebarFile)) as? [String: Any],
              let containers = (root["sidebar"] as? [String: Any])?["containers"] as? [Any],
              let container = containers.compactMap({ $0 as? [String: Any] }).first(where: { $0["spaces"] != nil })
        else { throw ImportError.unreadable }
        let reader = Reader(items: objects(container["items"]))

        // Favorites belong to a profile: the list alternates a profile and its container's id.
        var favoritesByProfile: [String: [ImportedItem]] = [:]
        let topApps = container["topAppsContainerIDs"] as? [Any] ?? []
        for index in stride(from: 0, to: topApps.count - 1, by: 2) {
            if let id = topApps[index + 1] as? String {
                favoritesByProfile[profileName(topApps[index])] = reader.children(of: id)
            }
        }

        return objects(container["spaces"]).compactMap { space in
            guard let id = space["id"] as? String else { return nil }
            let profile = profileName(space["profile"])
            let containerIDs = space["containerIDs"] as? [Any] ?? []
            func container(_ name: String) -> String? {
                guard let index = containerIDs.firstIndex(where: { $0 as? String == name }), index + 1 < containerIDs.count else { return nil }
                return containerIDs[index + 1] as? String
            }
            let info = space["customInfo"] as? [String: Any]
            // Arc's favorites are the icons at the top, Flux's pinned tabs, and Arc's pinned tabs
            // with their folders are Flux's favorites.
            return ImportedSpace(
                id: id,
                name: space["title"] as? String ?? "Arc",
                icon: emoji(info?["iconType"]),
                color: color(info?["windowTheme"]),
                profileFolder: profileFolder(profile),
                pinned: favoritesByProfile[profile] ?? [],
                favorites: container("pinned").map(reader.children(of:)) ?? [],
                today: container("unpinned").map(reader.children(of:)) ?? []
            )
        }
    }

    private struct Reader {
        let items: [String: [String: Any]]

        init(items: [[String: Any]]) {
            var byID: [String: [String: Any]] = [:]
            for item in items {
                if let id = item["id"] as? String { byID[id] = item }
            }
            self.items = byID
        }

        func children(of id: String) -> [ImportedItem] {
            (items[id]?["childrenIds"] as? [String] ?? []).compactMap(item)
        }

        private func tab(_ id: String) -> ImportedTab? {
            guard let item = items[id], let data = (item["data"] as? [String: Any])?["tab"] as? [String: Any],
                  let url = data["savedURL"] as? String, !url.isEmpty else { return nil }
            // A title the user gave the tab comes before the page's.
            let title = item["title"] as? String ?? data["savedTitle"] as? String ?? ""
            // Arc's own pages are Chromium's, under another name.
            return ImportedTab(title: title, url: url.hasPrefix("arc://") ? "chrome://" + url.dropFirst(6) : url)
        }

        private func item(_ id: String) -> ImportedItem? {
            guard let item = items[id], let data = item["data"] as? [String: Any] else { return nil }
            if let tab = tab(id) {
                return .tab(tab)
            }
            if data["list"] != nil {
                return .folder(title: item["title"] as? String ?? String(localized: "Folder"), items: children(of: id))
            }
            if let split = data["splitView"] as? [String: Any] {
                let ids = item["childrenIds"] as? [String] ?? []
                let tabs = ids.compactMap(tab)
                guard !tabs.isEmpty else { return nil }
                // Alternates a child's id and its factor. Children without one share the rest.
                var factors: [String: Double] = [:]
                let list = split["itemWidthFactors"] as? [Any] ?? []
                for index in stride(from: 0, to: list.count - 1, by: 2) {
                    if let child = list[index] as? String, let factor = list[index + 1] as? Double { factors[child] = factor }
                }
                let shares = ids.filter { tab($0) != nil }.map { factors[$0] }
                let shown = factors.count == tabs.count ? shares : Array(repeating: nil as Double?, count: tabs.count)
                return .split(tabs: tabs, shares: shown, isVertical: split["layoutOrientation"] as? String == "vertical")
            }
            // Easels, notes and other Arc-only items have no counterpart.
            return nil
        }
    }

    private static func objects(_ value: Any?) -> [[String: Any]] {
        (value as? [Any] ?? []).compactMap { $0 as? [String: Any] }
    }

    /// {"default": true}, or {"custom": {"_0": {"directoryBasename": "Profile 2"}}}.
    private static func profileName(_ value: Any?) -> String {
        let custom = ((value as? [String: Any])?["custom"] as? [String: Any])?["_0"] as? [String: Any]
        return custom?["directoryBasename"] as? String ?? "Default"
    }

    private static func emoji(_ value: Any?) -> String? {
        guard let icon = value as? [String: Any] else { return nil }
        if let emoji = icon["emoji_v2"] as? String, !emoji.isEmpty { return emoji }
        if let code = icon["emoji"] as? Int, let scalar = Unicode.Scalar(code) { return String(scalar) }
        return nil
    }

    /// The middle tone of the space's theme, the color Arc uses for its accents.
    private static func color(_ theme: Any?) -> String? {
        let palette = (theme as? [String: Any])?["primaryColorPalette"] as? [String: Any]
        guard let tone = palette?["midTone"] as? [String: Any] else { return nil }
        func component(_ key: String) -> Int {
            Int((min(max(tone[key] as? Double ?? 0, 0), 1) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", component("red"), component("green"), component("blue"))
    }
}
