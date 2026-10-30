import AppKit
import SwiftUI

/// The browsers Flux imports from. Those built on Chromium bring history, passwords, sign-ins and
/// extensions the same way: only their sidebars differ. Firefox brings its bookmarks and history.
enum ImportSource: CaseIterable, Identifiable {
    case arc, dia, chrome, brave, edge, firefox

    var id: Self { self }

    var name: String {
        switch self {
        case .arc: "Arc"
        case .dia: "Dia"
        case .chrome: "Google Chrome"
        case .brave: "Brave"
        case .edge: "Microsoft Edge"
        case .firefox: "Firefox"
        }
    }

    var isChromium: Bool {
        self != .firefox
    }

    private var bundleIdentifier: String {
        switch self {
        case .arc: "company.thebrowser.Browser"
        case .dia: "company.thebrowser.dia"
        case .chrome: "com.google.Chrome"
        case .brave: "com.brave.Browser"
        case .edge: "com.microsoft.edgemac"
        case .firefox: "org.mozilla.firefox"
        }
    }

    /// Chrome, Brave and Edge keep their profiles right in this folder of Application Support.
    private var chromiumProfiles: ChromiumProfiles? {
        let support = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return switch self {
        case .arc, .dia, .firefox: nil
        case .chrome: ChromiumProfiles(root: support.appending(path: "Google/Chrome", directoryHint: .isDirectory))
        case .brave: ChromiumProfiles(root: support.appending(path: "BraveSoftware/Brave-Browser", directoryHint: .isDirectory))
        case .edge: ChromiumProfiles(root: support.appending(path: "Microsoft Edge", directoryHint: .isDirectory))
        }
    }

    /// Installed, which is enough to list it: macOS may only let Flux read its data once asked.
    var isAvailable: Bool {
        switch self {
        case .arc: ArcLibrary.isInstalled
        case .dia: DiaLibrary.isInstalled
        default: NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
        }
    }

    var icon: NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    func loadSpaces() throws -> [ImportedSpace] {
        switch self {
        case .arc: try ArcLibrary.loadSpaces()
        case .dia: try DiaLibrary.loadSpaces()
        case .firefox: try FirefoxLibrary.loadSpaces()
        default: try ChromiumBrowserLibrary.loadSpaces(from: chromiumProfiles!)
        }
    }

    /// The space the browser showed last, which Flux shows once the import is done.
    var lastSpaceID: String? {
        switch self {
        case .arc: ArcLibrary.lastSpaceID
        case .dia: DiaLibrary.lastSpaceID
        case .firefox: FirefoxLibrary.lastSpaceID
        default: chromiumProfiles?.lastUsed
        }
    }

    /// Where Chromium keeps the key of this browser's passwords and cookies.
    var keychainItem: (service: String, account: String)? {
        switch self {
        case .firefox: nil
        case .arc: ("Arc Safe Storage", "Arc")
        case .dia: ("Dia Safe Storage", "Dia")
        case .chrome: ("Chrome Safe Storage", "Chrome")
        case .brave: ("Brave Safe Storage", "Brave")
        case .edge: ("Microsoft Edge Safe Storage", "Microsoft Edge")
        }
    }

    /// History, passwords and sign-ins come with the browser's databases, which Flux's Chromium
    /// only opens when they aren't from a later version.
    var canTransferProfiles: Bool {
        let version = switch self {
        case .firefox: Int?.some(.max)
        case .arc: ChromiumProfiles(root: ArcLibrary.folder.appending(path: "User Data", directoryHint: .isDirectory)).chromiumVersion
        case .dia: DiaLibrary.chromiumVersion
        default: chromiumProfiles?.chromiumVersion
        }
        return (version ?? .max) <= FLXEngine.chromiumMajorVersion
    }

    /// Dia keeps its open tabs in a database of its own that is encrypted, and the others in
    /// sessions Flux doesn't read.
    var hasToday: Bool {
        self == .arc
    }

    /// Firefox protects its passwords with its own library: they come as a file the user exports.
    var exportsPasswords: Bool {
        self == .firefox
    }

    func siteIcons(in profileFolder: URL) -> any SiteIcons {
        isChromium ? ChromiumFavicons(profileFolder: profileFolder) : FirefoxFavicons(profileFolder: profileFolder)
    }

    /// Fills a Flux profile Chromium hasn't opened yet with what the browser's profile can give.
    @MainActor
    func prepare(_ folder: URL, from profileFolder: URL) {
        if isChromium {
            guard canTransferProfiles else { return }
            ProfileTransfer.transfer(from: profileFolder, to: folder, keys: ProfileTransfer.keys(for: self))
        } else {
            PendingHistory.stageFirefoxHistory(from: profileFolder, for: folder)
        }
    }

    /// The sources installed on this Mac whose spaces could be read.
    static func available() -> [(source: ImportSource, spaces: [ImportedSpace])] {
        allCases.filter(\.isAvailable).compactMap { source in
            guard let spaces = try? source.loadSpaces(), !spaces.isEmpty else { return nil }
            return (source, spaces)
        }
    }
}

/// macOS lets an app read another app's data only once the user allows it in Privacy & Security,
/// and since macOS 27 without asking: the user has to go there.
struct AppDataAccessHint: View {
    let sources: [ImportSource]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("To import \(sources.map(\.name).formatted(.list(type: .and))), allow Flux to read data from other apps in Privacy & Security, under Files & Folders.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
            }
            .controlSize(.small)
        }
    }
}

enum ImportError: Error {
    case unreadable
}
