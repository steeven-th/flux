import Foundation

/// Dia's profiles and their pinned tabs. Dia keeps its tabs in databases of its own that are
/// encrypted, but its pinned tabs are Chromium bookmarks: a "Favorites" folder for the icons, and
/// a folder per space Dia brought from Arc.
enum DiaLibrary {
    static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/Dia", directoryHint: .isDirectory)

    private static var profiles: ChromiumProfiles {
        ChromiumProfiles(root: folder.appending(path: "User Data", directoryHint: .isDirectory))
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: profiles.root.appending(path: "Local State").path)
    }

    static var lastSpaceID: String? {
        profiles.lastUsed
    }

    static var chromiumVersion: Int? {
        profiles.chromiumVersion
    }

    static func loadSpaces() throws -> [ImportedSpace] {
        try profiles.list().map { profile in
            let bar = ChromiumProfiles.bookmarks(in: profile.folder).bar
            let favorites = bar.filter { !isFavoritesFolder($0) }
            let spaceFolders = favorites.filter { $0["type"] as? String == "folder" }
            // A single space's folder is the space itself: its content comes up a level.
            let content = spaceFolders.count == 1 && favorites.count == 1
                ? ChromiumProfiles.children(of: spaceFolders[0])
                : favorites.compactMap(ChromiumProfiles.item)
            var name = profile.name
            // Chromium names a profile nobody named after itself.
            if name.contains("Chromium") {
                name = spaceFolders.count == 1 ? spaceFolders[0]["name"] as? String ?? "Dia" : "Dia"
            }
            return ImportedSpace(
                id: profile.directory,
                name: name,
                icon: nil,
                color: profile.color,
                profileFolder: profile.folder,
                pinned: bar.first(where: isFavoritesFolder).map(ChromiumProfiles.children(of:)) ?? [],
                favorites: content,
                today: []
            )
        }
    }

    private static func isFavoritesFolder(_ node: [String: Any]) -> Bool {
        node["type"] as? String == "folder" && node["name"] as? String == "Favorites"
    }
}
