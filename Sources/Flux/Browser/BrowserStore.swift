import AppKit
import Observation

/// What every window shares: the spaces with their tabs, folders and splits, the profiles and
/// their databases. Each window has a BrowserState of its own over it, which holds what it shows.
@MainActor
@Observable
final class BrowserStore {
    var spaces: [Space] = []
    var tabs: [Tab] = []
    var folders: [Folder] = []
    var splits: [Split] = []
    var sidebarRevision = 0
    var archiveRevision = 0
    var settingsRevision = 0
    var linkRules: [LinkRule] = []
    /// One per window, in the order they opened.
    var windows: [BrowserState] = []
    /// Private windows share a store of their own, with one space and nothing on disk.
    let isPrivate: Bool
    /// The private windows' store while one is open.
    static weak var privateStore: BrowserStore?

    init(isPrivate: Bool = false) {
        self.isPrivate = isPrivate
    }

    @ObservationIgnored var spaceRecords: [UUID: SpaceRecord] = [:]
    @ObservationIgnored var profiles: [UUID: FLXProfile] = [:]
    @ObservationIgnored var profileDatabases: [UUID: ProfileDatabase] = [:]
    @ObservationIgnored var extensionLists: [UUID: ExtensionList] = [:]
    @ObservationIgnored var faviconCaches: [UUID: FaviconCache] = [:]
    @ObservationIgnored var histories: [UUID: ChromiumHistory] = [:]
    @ObservationIgnored var passwordManagers: [UUID: ChromiumPasswordManager] = [:]
    @ObservationIgnored var downloadLists: [String: DownloadList] = [:]
    @ObservationIgnored var media: MediaLibrary?
    @ObservationIgnored var archiveTimer: Timer?
    @ObservationIgnored var scrollTimer: Timer?
    @ObservationIgnored var sleepTimer: Timer?
    @ObservationIgnored var onExtensionInstall: ((InstalledExtension, UUID) -> Void)?
}
