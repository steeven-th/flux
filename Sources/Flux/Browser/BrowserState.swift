import Foundation
import Observation
import os

@MainActor
@Observable
final class BrowserState {
    static let spaceColors = ["#F97316", "#3B82F6", "#22C55E", "#A855F7", "#EC4899", "#EAB308", "#14B8A6", "#EF4444"]
    private static let selectedSpaceKey = "selectedSpaceID"
    private static let confirmsTabRemovalKey = "confirmsTabRemoval"
    private static let searchEngineKey = "searchEngine"
    private static let sidebarWidthKey = "sidebarWidth"
    private static let sidebarCollapsedKey = "sidebarCollapsed"
    private static let warnsBeforeQuittingKey = "warnsBeforeQuitting"
    private static let fullScreenKey = "windowFullScreen"
    private static let asksWhereToSaveKey = "asksWhereToSaveDownloads"
    private static let unpinnedExtensionsKey = "unpinnedExtensions"
    private static let developerSitesKey = "developerSites"
    private static let devToolsWidthKey = "devToolsWidth"
    private static let devToolsOrderKey = "devToolsOrder"
    private static let devToolsShownKey = "devToolsShown"
    private static let responsiveBackdropKey = "responsiveBackdrop"
    private static let responsiveOptionsKey = "responsiveOptions"
    private static let translationProviderKey = "translationProvider"
    private static let translatedCharactersKey = "translatedCharacters"
    private static let importedExtensionsKey = "importedExtensions"
    private static let importedExtensionsCardHiddenKey = "importedExtensionsCardHidden"
    private static let passwordExportKey = "passwordExport"
    private static let tabSleepDelayKey = "tabSleepDelay"
    private static let hiddenDevicesKey = "hiddenDevices"
    private static let customDevicesKey = "customDevices"
    private static let archiveDelayKey = "archiveDelay"
    private static let linkTargetsOpenPeekKey = "linkTargetsOpenPeek"
    private static let shiftClickOpensPeekKey = "shiftClickOpensPeek"
    private static let outsideLinksOpenLittleWindowKey = "outsideLinksOpenLittleWindow"
    /// Archived tabs are kept this long. The pages stay in the history after that.
    private static let archiveLifetime: TimeInterval = 30 * 86_400
    private static let logger = Logger(subsystem: "com.flux-browser.Flux", category: "storage")

    private(set) var spaces: [Space] = []
    private(set) var tabs: [Tab] = []
    private(set) var folders: [Folder] = []
    private(set) var splits: [Split] = []
    /// Bumped whenever the sidebar's structure changes: items added, removed or moved.
    private(set) var sidebarRevision = 0
    /// Bumped when the archive changes, since it is read from the database.
    private(set) var archiveRevision = 0
    var isArchiveShown = false
    /// A tab being dragged from the sidebar, which can be dropped on the pages to split them.
    var draggedTab: Tab?
    /// Downloads and media, shown in place of the sidebar.
    var isLibraryShown = false
    /// Bumped when a setting read from the database changes, for views showing it.
    private(set) var settingsRevision = 0
    /// A page opened from a link, shown over the selected tab.
    private(set) var peek: Peek?
    @ObservationIgnored private var archiveTimer: Timer?
    @ObservationIgnored private var scrollTimer: Timer?
    @ObservationIgnored private var sleepTimer: Timer?
    /// Each space's selected tab, saved in its space record as well.
    private var selectedTabIDs: [UUID: UUID] = [:]
    var selectedSpaceID: UUID {
        willSet { selectedTab?.saveScrollPosition() }
        didSet { save { try appDatabase.setSetting(Self.selectedSpaceKey, to: selectedSpaceID.uuidString) } }
    }

    @ObservationIgnored private let appDatabase: AppDatabase
    @ObservationIgnored private var spaceRecords: [UUID: SpaceRecord] = [:]
    @ObservationIgnored private var profiles: [UUID: FLXProfile] = [:]
    @ObservationIgnored private var profileDatabases: [UUID: ProfileDatabase] = [:]
    @ObservationIgnored private var extensionLists: [UUID: ExtensionList] = [:]
    @ObservationIgnored private var faviconCaches: [UUID: FaviconCache] = [:]
    @ObservationIgnored private var histories: [UUID: ChromiumHistory] = [:]
    @ObservationIgnored private var passwordManagers: [UUID: ChromiumPasswordManager] = [:]
    /// By profile folder: spaces sharing a profile share its downloads.
    @ObservationIgnored private var downloadLists: [String: DownloadList] = [:]
    @ObservationIgnored private var media: MediaLibrary?

    init(appDatabase: AppDatabase) throws {
        self.appDatabase = appDatabase
        var records = try appDatabase.spaces()
        if records.isEmpty {
            // The welcome window creates the first space, so this only happens if it was skipped.
            records = [try Self.createFirstSpace(name: String(localized: "Personal"), icon: nil, color: Self.spaceColors[0], in: appDatabase)]
        }
        FLXProfile.languagesProvider = { _ in Self.systemLanguageList }
        let savedSelection = try appDatabase.setting(Self.selectedSpaceKey).flatMap(UUID.init(uuidString:))
        selectedSpaceID = records.first { $0.id == savedSelection }?.id ?? records[0].id

        for record in records {
            try open(record)
        }
        PageTranslator.shared.configure(translationProvider)
        PageTranslator.shared.onCharactersSent = { [weak self] count in self?.recordTranslatedCharacters(count) }
    }

    static func createFirstSpace(name: String, icon: String?, color: String, in database: AppDatabase) throws -> SpaceRecord {
        let id = UUID()
        let record = SpaceRecord(
            id: id, name: name, icon: icon, color: color, position: FractionalIndex.between(nil, nil),
            profileFolder: "Profile \(id.uuidString)", selectedTabID: nil, createdAt: Date()
        )
        try database.save(record)
        return record
    }

    private func open(_ record: SpaceRecord) throws {
        let space = Space(record: record)
        let database = try ProfileDatabase(profileFolder: space.profileFolder)
        let profile = FLXProfile(atPath: space.profileFolder.path)
        spaces.append(space)
        spaceRecords[space.id] = record
        selectedTabIDs[space.id] = record.selectedTabID
        profiles[space.id] = profile
        profileDatabases[space.id] = database
        extensionLists[space.id] = ExtensionList(profile: profile, profileFolder: space.profileFolder)
        faviconCaches[space.id] = FaviconCache(profileFolder: space.profileFolder)
        histories[space.id] = ChromiumHistory(profileFolder: space.profileFolder)
        passwordManagers[space.id] = ChromiumPasswordManager(profile: profile)
        if downloadLists[profile.path] == nil {
            downloadLists[profile.path] = DownloadList(profile: profile, database: database)
        }
        profile.asksWhereToSaveDownloads = asksWhereToSaveDownloads(forProfile: space.profileFolder)
        // Chromium's translation needs Google keys Flux doesn't have, so its offers would lead
        // nowhere.
        profile.setPreference("translate.enabled", boolValue: false)

        let nodes = try database.nodes(in: space.id)
        for node in nodes {
            switch node.kind {
            case .tab: tabs.append(makeTab(node))
            case .folder: folders.append(Folder(node: node))
            case .split: splits.append(Split(node: node))
            }
        }
        for split in splits where split.spaceID == space.id {
            dissolveIfNeeded(split)
        }
    }

    private func makeTab(_ node: SidebarNode, page: FLXBrowserView? = nil) -> Tab {
        let tab = Tab(node: node, profile: profiles[node.spaceID]!, favicons: faviconCaches[node.spaceID]!, page: page)
        tab.onChange = { [weak self] tab in
            self?.save { try self?.profileDatabases[tab.spaceID]?.save(tab.node) }
        }
        tab.onOpenPage = { [weak self] opener, page, disposition in
            self?.open(page, from: opener.spaceID, disposition: disposition)
        }
        return tab
    }

    /// A new space gets a profile of its own, so nothing is shared with other spaces, unless it is
    /// to share another space's.
    @discardableResult
    func createSpace(
        name: String, icon: String?, color: String, sharingProfileOf other: UUID? = nil,
        preparingProfile prepare: ((URL) -> Void)? = nil
    ) -> UUID {
        let id = UUID()
        let lastPosition = spaces.last.flatMap { spaceRecords[$0.id]?.position }
        let record = SpaceRecord(
            id: id, name: name, icon: icon, color: color,
            position: FractionalIndex.between(lastPosition, nil),
            profileFolder: other.flatMap { spaceRecords[$0]?.profileFolder } ?? "Profile \(id.uuidString)",
            selectedTabID: nil, createdAt: Date()
        )
        save { try appDatabase.save(record) }
        // Before Chromium opens the profile, which it does as soon as the space opens.
        if other == nil { prepare?(AppPaths.profileFolder(named: record.profileFolder)) }
        save { try open(record) }
        selectedSpaceID = id
        return id
    }

    func updateSpace(_ id: UUID, name: String, icon: String?, color: String) {
        guard var record = spaceRecords[id], let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        record.name = name
        record.icon = icon
        record.color = color
        spaceRecords[id] = record
        spaces[index] = Space(record: record)
        save { try appDatabase.save(record) }
    }

    /// True when no other space uses this space's profile, so deleting the space deletes the
    /// profile's sign-ins, passwords and extensions too.
    func ownsProfile(_ id: UUID) -> Bool {
        guard let folder = spaceRecords[id]?.profileFolder else { return false }
        return !spaceRecords.values.contains { $0.id != id && $0.profileFolder == folder }
    }

    func deleteSpace(_ id: UUID) {
        guard spaces.count > 1, let record = spaceRecords[id] else { return }
        let ownsProfile = ownsProfile(id)
        let database = profileDatabases[id]

        for tab in tabs where tab.spaceID == id {
            tab.close()
        }
        tabs.removeAll { $0.spaceID == id }
        spaces.removeAll { $0.id == id }
        spaceRecords[id] = nil
        selectedTabIDs[id] = nil
        profiles[id] = nil
        profileDatabases[id] = nil
        extensionLists[id] = nil
        faviconCaches[id] = nil
        histories[id] = nil
        passwordManagers[id] = nil
        folders.removeAll { $0.spaceID == id }
        splits.removeAll { $0.spaceID == id }
        sidebarRevision += 1
        if selectedSpaceID == id {
            selectedSpaceID = spaces[0].id
        }

        save { try appDatabase.delete(record) }
        if ownsProfile {
            save { try appDatabase.scheduleDeletion(ofProfileFolder: record.profileFolder) }
        } else {
            save { try database?.deleteNodes(in: id) }
            save { try database?.clearArchive(in: id) }
        }
    }

    func selectSpace(at index: Int) {
        guard spaces.indices.contains(index) else { return }
        selectedSpaceID = spaces[index].id
    }

    var selectedSpace: Space {
        spaces.first { $0.id == selectedSpaceID } ?? spaces[0]
    }

    var selectedProfile: FLXProfile {
        profiles[selectedSpaceID]!
    }

    var extensionsInSelectedSpace: [InstalledExtension] {
        extensionLists[selectedSpaceID]?.extensions ?? []
    }

    var tabsInSelectedSpace: [Tab] {
        tabs.filter { $0.spaceID == selectedSpaceID }
    }

    var selectedTab: Tab? {
        let id = selectedTabIDs[selectedSpaceID]
        return tabs.first { $0.id == id } ?? tabsInSelectedSpace.last
    }

    /// Whether removing a pinned tab or a favorite asks first. On unless the user turned it off.
    var confirmsTabRemoval: Bool {
        get { (try? appDatabase.setting(Self.confirmsTabRemovalKey)) != "false" }
        set { save { try appDatabase.setSetting(Self.confirmsTabRemovalKey, to: newValue ? nil : "false") } }
    }

    /// Nil until the user resizes the sidebar.
    var sidebarWidth: CGFloat? {
        get { (try? appDatabase.setting(Self.sidebarWidthKey)).flatMap { Double($0) }.map { CGFloat($0) } }
        set { save { try appDatabase.setSetting(Self.sidebarWidthKey, to: newValue.map { String(Double($0)) }) } }
    }

    var isSidebarCollapsed: Bool {
        get { (try? appDatabase.setting(Self.sidebarCollapsedKey)) == "true" }
        set { save { try appDatabase.setSetting(Self.sidebarCollapsedKey, to: newValue ? "true" : nil) } }
    }

    var isWindowFullScreen: Bool {
        get { (try? appDatabase.setting(Self.fullScreenKey)) == "true" }
        set { save { try appDatabase.setSetting(Self.fullScreenKey, to: newValue ? "true" : nil) } }
    }

    var warnsBeforeQuitting: Bool {
        get { (try? appDatabase.setting(Self.warnsBeforeQuittingKey)) == "true" }
        set { save { try appDatabase.setSetting(Self.warnsBeforeQuittingKey, to: newValue ? "true" : nil) } }
    }

    /// The selected space's, since each profile has its own.
    var searchEngine: SearchEngine {
        searchEngine(forProfile: selectedSpace.profileFolder)
    }

    /// Profiles without a choice of their own use the engine chosen before engines were per
    /// profile, or Google.
    func searchEngine(forProfile folder: URL) -> SearchEngine {
        let own = try? appDatabase.setting(Self.searchEngineKey(forProfile: folder))
        return SearchEngine(setting: own ?? (try? appDatabase.setting(Self.searchEngineKey)))
    }

    func setSearchEngine(_ engine: SearchEngine, forProfile folder: URL) {
        save { try appDatabase.setSetting(Self.searchEngineKey(forProfile: folder), to: engine.id) }
    }

    private static func searchEngineKey(forProfile folder: URL) -> String {
        "\(searchEngineKey) \(folder.lastPathComponent)"
    }

    struct Profile: Identifiable {
        let folder: URL
        let spaces: [Space]

        var id: URL { folder }

        /// Profiles have no name of their own, they're named after their spaces.
        var name: String {
            spaces.map(\.name).joined(separator: ", ")
        }
    }

    func extensionList(forProfile folder: URL) -> ExtensionList? {
        firstSpace(usingProfile: folder).flatMap { extensionLists[$0.id] }
    }

    func passwordManager(forProfile folder: URL) -> ChromiumPasswordManager? {
        firstSpace(usingProfile: folder).flatMap { passwordManagers[$0.id] }
    }

    private func firstSpace(usingProfile folder: URL) -> Space? {
        spaces.first { $0.profileFolder.standardizedFileURL == folder.standardizedFileURL }
    }

    /// The profiles in use, in the order of their first space.
    var profilesInUse: [Profile] {
        var folders: [URL] = []
        var spacesByFolder: [URL: [Space]] = [:]
        for space in spaces {
            let folder = space.profileFolder.standardizedFileURL
            if spacesByFolder[folder] == nil { folders.append(folder) }
            spacesByFolder[folder, default: []].append(space)
        }
        return folders.map { Profile(folder: $0, spaces: spacesByFolder[$0] ?? []) }
    }

    func select(_ tab: Tab) {
        guard selectedTabIDs[tab.spaceID] != tab.id else { return }
        selectedTab?.saveScrollPosition()
        // Seen until now: a tab looked at for a long time is not inactive the moment it is left.
        for shown in shownTabs where shown !== tab { shown.markActive() }
        selectedTabIDs[tab.spaceID] = tab.id
        if var record = spaceRecords[tab.spaceID] {
            record.selectedTabID = tab.id
            spaceRecords[tab.spaceID] = record
            save { try appDatabase.save(record) }
        }
        tab.markActive()
    }

    @discardableResult
    func newTab(
        url: String, in spaceID: UUID? = nil, page: FLXBrowserView? = nil, selecting: Bool = true
    ) -> Tab {
        let spaceID = spaceID ?? selectedSpaceID
        // Without a stored selection the last tab shows, which the new one is about to become.
        if !selecting, selectedTabIDs[spaceID].flatMap({ id in tabs.first { $0.id == id } }) == nil {
            selectedTabIDs[spaceID] = tabs.last { $0.spaceID == spaceID }?.id
        }
        let last = entries(in: .today, parentID: nil, spaceID: spaceID).last?.node.position
        let node = SidebarNode(
            id: UUID(), spaceID: spaceID, parentID: nil, kind: .tab, section: .today,
            position: FractionalIndex.between(last, nil), title: "", url: url, originalURL: nil,
            isExpanded: true, lastActiveAt: Date(), createdAt: Date()
        )
        save { try profileDatabases[spaceID]?.save(node) }
        let tab = makeTab(node, page: page)
        tabs.append(tab)
        sidebarRevision += 1
        if selecting { select(tab) }
        return tab
    }

    /// Pinned tabs and favorites are only unloaded, like in Arc. Other tabs go away.
    func close(_ tab: Tab) {
        close(tab, removing: !tab.isKept)
    }

    /// Takes a kept tab out of the sidebar for good.
    func remove(_ tab: Tab) {
        close(tab, removing: true)
    }

    /// Frees the page's memory. The tab stays in the sidebar and loads again when shown.
    func unload(_ tab: Tab) {
        close(tab, removing: false)
    }

    private func close(_ tab: Tab, removing: Bool) {
        let wasSelected = selectedTab?.id == tab.id
        let split = split(of: tab)
        let otherPanes = split.map(panes(of:))?.filter { $0 !== tab } ?? []
        if !removing {
            tab.unload()
        } else {
            if tab.node.section == .today {
                archive(tab)
            }
            tabs.removeAll { $0 === tab }
            tab.close()
            save { try profileDatabases[tab.spaceID]?.delete(nodeID: tab.id) }
            if let split { dissolveIfNeeded(split) }
            sidebarRevision += 1
        }
        if wasSelected {
            // Another pane of the split, if it stays, rather than another tab.
            if removing, let pane = otherPanes.first {
                select(pane)
                return
            }
            let candidates = tabs.filter { $0.spaceID == tab.spaceID && $0 !== tab && ($0.isLoaded || !$0.isKept) }
            if let next = candidates.max(by: { ($0.node.lastActiveAt ?? .distantPast) < ($1.node.lastActiveAt ?? .distantPast) }) {
                select(next)
            } else {
                selectedTabIDs[tab.spaceID] = nil
            }
        }
    }

    var tabSleepDelay: TabSleepDelay {
        get {
            _ = settingsRevision
            return (try? appDatabase.setting(Self.tabSleepDelayKey)).flatMap(TabSleepDelay.init) ?? .standard
        }
        set {
            save { try appDatabase.setSetting(Self.tabSleepDelayKey, to: newValue == .standard ? nil : newValue.rawValue) }
            settingsRevision += 1
        }
    }

    /// Chromium's memory saver only knows its own tab strip, where each of Flux's pages is the
    /// active tab of a window of its own: Flux unloads the pages left unseen itself.
    func startSleepingTabs() {
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleepInactiveTabs() }
        }
    }

    private func sleepInactiveTabs() {
        guard let interval = tabSleepDelay.interval else { return }
        let limit = Date().addingTimeInterval(-interval)
        let shown = shownTabs
        let inactive = tabs.filter { tab in
            tab.isLoaded && tab.devTools == nil && !shown.contains { $0 === tab }
                && (tab.node.lastActiveAt ?? tab.node.createdAt) < limit
        }
        for tab in inactive {
            // A page playing sound or a video keeps playing.
            tab.browserView.evaluateJavaScript(
                "String([...document.querySelectorAll('audio, video')].some(m => !m.paused && !m.ended))"
            ) { [weak self, weak tab] value in
                guard let self, let tab, value as? String != "true", tab.isLoaded,
                      !self.shownTabs.contains(where: { $0 === tab }) else { return }
                self.unload(tab)
            }
        }
    }

    /// Saves where the page shown is scrolled every few seconds. Pages answer asynchronously, so
    /// Flux can't ask them when it quits, or when it crashes.
    func startSavingScrollPositions() {
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard NSApp.isActive else { return }
                self?.selectedTab?.saveScrollPosition()
            }
        }
    }

    // Peek.

    /// Whether links opening a new tab, with a target or window.open, show in a Peek.
    var linkTargetsOpenPeek: Bool {
        get { (try? appDatabase.setting(Self.linkTargetsOpenPeekKey)) != "false" }
        set { save { try appDatabase.setSetting(Self.linkTargetsOpenPeekKey, to: newValue ? nil : "false") } }
    }

    var shiftClickOpensPeek: Bool {
        get { (try? appDatabase.setting(Self.shiftClickOpensPeekKey)) != "false" }
        set { save { try appDatabase.setSetting(Self.shiftClickOpensPeekKey, to: newValue ? nil : "false") } }
    }

    /// A page opened by another one goes to a Peek, or to a tab of the same space.
    private func open(_ page: FLXBrowserView, from spaceID: UUID, disposition: FLXOpenDisposition) {
        let peeks = switch disposition {
        case .linkTarget: linkTargetsOpenPeek
        case .shiftClick: shiftClickOpensPeek
        default: false
        }
        guard peeks, spaceID == selectedSpaceID else {
            newTab(url: page.currentURL, in: spaceID, page: page, selecting: disposition != .backgroundTab)
            return
        }
        closePeek()
        let peek = Peek(page: page, spaceID: spaceID, favicon: faviconCaches[spaceID]?.image(for: page.currentURL))
        // Links opened from a Peek become tabs: Peeks don't stack.
        peek.onOpenPage = { [weak self] page, disposition in
            self?.newTab(url: page.currentURL, in: spaceID, page: page, selecting: disposition != .backgroundTab)
        }
        peek.onClose = { [weak self, weak peek] in
            if let peek, self?.peek === peek { self?.peek = nil }
        }
        self.peek = peek
    }

    func closePeek() {
        guard let peek else { return }
        self.peek = nil
        peek.page.close()
    }

    /// Moves the Peek's page into a tab of Today, without loading it again.
    func openPeekInTab() {
        guard let peek else { return }
        self.peek = nil
        adopt(peek.page, url: peek.url, title: peek.title, favicon: peek.favicon, in: peek.spaceID)
    }

    /// Makes a page shown elsewhere a tab of Today in the space, and shows it.
    func adopt(_ page: FLXBrowserView, url: String, title: String, favicon: NSImage?, in spaceID: UUID) {
        selectedSpaceID = spaceID
        let tab = newTab(url: url, in: spaceID, page: page)
        tab.browserView(page, didChangeTitle: title)
        if let favicon { tab.browserView(page, didChangeFavicon: favicon) }
    }

    /// Whether links from other apps open in a little window rather than a tab.
    var outsideLinksOpenLittleWindow: Bool {
        get { (try? appDatabase.setting(Self.outsideLinksOpenLittleWindowKey)) != "false" }
        set { save { try appDatabase.setSetting(Self.outsideLinksOpenLittleWindowKey, to: newValue ? nil : "false") } }
    }

    var downloadsOfSelectedSpace: DownloadList? {
        profiles[selectedSpaceID].flatMap { downloadLists[$0.path] }
    }

    /// Created on first use: reading the Downloads folder makes macOS ask for access.
    var mediaLibrary: MediaLibrary {
        if let media { return media }
        let media = MediaLibrary()
        self.media = media
        return media
    }

    func asksWhereToSaveDownloads(forProfile folder: URL) -> Bool {
        (try? appDatabase.setting(Self.asksWhereToSaveKey(forProfile: folder))) == "true"
    }

    func setAsksWhereToSaveDownloads(_ asks: Bool, forProfile folder: URL) {
        save { try appDatabase.setSetting(Self.asksWhereToSaveKey(forProfile: folder), to: asks ? "true" : nil) }
        for space in spaces where space.profileFolder.standardizedFileURL == folder.standardizedFileURL {
            profiles[space.id]?.asksWhereToSaveDownloads = asks
        }
    }

    private static func asksWhereToSaveKey(forProfile folder: URL) -> String {
        "\(asksWhereToSaveKey) \(folder.lastPathComponent)"
    }

    // Extensions shown next to the address. All of them unless the user unpinned some.

    var pinnedExtensionsInSelectedSpace: [InstalledExtension] {
        let unpinned = unpinnedExtensions(forProfile: selectedSpace.profileFolder)
        return extensionsInSelectedSpace.filter { !unpinned.contains($0.id) }
    }

    func isPinned(_ item: InstalledExtension) -> Bool {
        !unpinnedExtensions(forProfile: selectedSpace.profileFolder).contains(item.id)
    }

    func togglePin(_ item: InstalledExtension) {
        var unpinned = unpinnedExtensions(forProfile: selectedSpace.profileFolder)
        if unpinned.contains(item.id) { unpinned.remove(item.id) } else { unpinned.insert(item.id) }
        saveSet(unpinned, key: Self.unpinnedExtensionsKey, profile: selectedSpace.profileFolder)
    }

    private func unpinnedExtensions(forProfile folder: URL) -> Set<String> {
        _ = settingsRevision
        return loadSet(key: Self.unpinnedExtensionsKey, profile: folder)
    }

    // Developer mode is turned on for a site, in one profile.

    func isDeveloperMode(for url: String) -> Bool {
        _ = settingsRevision
        guard let host = URL(string: url)?.host() else { return false }
        return loadSet(key: Self.developerSitesKey, profile: selectedSpace.profileFolder).contains(host)
    }

    /// Every tool, in the order the user chose. Tools added to Flux later come at the end.
    var devToolsOrder: [DevTool] {
        get {
            _ = settingsRevision
            let saved = (try? appDatabase.setting(Self.devToolsOrderKey))
                .flatMap { try? JSONDecoder().decode([DevTool].self, from: Data($0.utf8)) } ?? DevTool.allCases
            return saved + DevTool.allCases.filter { !saved.contains($0) }
        }
        set {
            save { try appDatabase.setSetting(Self.devToolsOrderKey, to: String(data: try JSONEncoder().encode(newValue), encoding: .utf8)) }
            settingsRevision += 1
        }
    }

    var shownDevTools: Set<DevTool> {
        get {
            _ = settingsRevision
            return (try? appDatabase.setting(Self.devToolsShownKey))
                .flatMap { try? JSONDecoder().decode(Set<DevTool>.self, from: Data($0.utf8)) } ?? Set(DevTool.standard)
        }
        set {
            save { try appDatabase.setSetting(Self.devToolsShownKey, to: String(data: try JSONEncoder().encode(newValue), encoding: .utf8)) }
            settingsRevision += 1
        }
    }

    /// The tools of the developer bar, in order.
    var devToolsInBar: [DevTool] {
        let shown = shownDevTools
        return devToolsOrder.filter { shown.contains($0) }
    }

    var devToolsWidth: CGFloat {
        get { (try? appDatabase.setting(Self.devToolsWidthKey)).flatMap { Double($0) }.map { CGFloat($0) } ?? 480 }
        set { save { try appDatabase.setSetting(Self.devToolsWidthKey, to: String(Double(newValue))) } }
    }

    var responsiveBackdrop: ResponsiveBackdrop {
        get {
            _ = settingsRevision
            return (try? appDatabase.setting(Self.responsiveBackdropKey)).flatMap(ResponsiveBackdrop.init) ?? .system
        }
        set {
            save { try appDatabase.setSetting(Self.responsiveBackdropKey, to: newValue == .system ? nil : newValue.rawValue) }
            settingsRevision += 1
        }
    }

    /// What the responsive mode's toolbar shows beyond the size, from its options menu.
    var responsiveOptions: Set<ResponsiveOption> {
        get {
            _ = settingsRevision
            return (try? appDatabase.setting(Self.responsiveOptionsKey))
                .flatMap { try? JSONDecoder().decode(Set<ResponsiveOption>.self, from: Data($0.utf8)) } ?? []
        }
        set {
            save { try appDatabase.setSetting(Self.responsiveOptionsKey, to: String(data: try JSONEncoder().encode(newValue), encoding: .utf8)) }
            settingsRevision += 1
        }
    }

    /// Built-in devices the user unchecked, by id.
    var hiddenDevices: Set<String> {
        get {
            _ = settingsRevision
            return (try? appDatabase.setting(Self.hiddenDevicesKey))
                .flatMap { try? JSONDecoder().decode(Set<String>.self, from: Data($0.utf8)) } ?? []
        }
        set {
            save { try appDatabase.setSetting(Self.hiddenDevicesKey, to: newValue.isEmpty ? nil : String(data: try JSONEncoder().encode(newValue), encoding: .utf8)) }
            settingsRevision += 1
        }
    }

    var customDevices: [EmulatedDevice] {
        get {
            _ = settingsRevision
            return (try? appDatabase.setting(Self.customDevicesKey))
                .flatMap { try? JSONDecoder().decode([EmulatedDevice].self, from: Data($0.utf8)) } ?? []
        }
        set {
            save { try appDatabase.setSetting(Self.customDevicesKey, to: newValue.isEmpty ? nil : String(data: try JSONEncoder().encode(newValue), encoding: .utf8)) }
            settingsRevision += 1
        }
    }

    /// The devices the responsive mode offers.
    var emulatedDevices: [EmulatedDevice] {
        let hidden = hiddenDevices
        return EmulatedDevice.all.filter { !hidden.contains($0.id) } + customDevices
    }

    /// The Mac's languages as Chromium lists them, each followed by its language without region.
    /// Profiles start with them, until the user chooses others in chrome://settings/languages.
    private static var systemLanguageList: String {
        let languages = UserDefaults(suiteName: ".GlobalPreferences")?.stringArray(forKey: "AppleLanguages") ?? ["en-US"]
        var list: [String] = []
        for language in languages {
            let code = Locale.Language(identifier: language)
            for item in [language, code.languageCode?.identifier].compactMap({ $0 }) where !list.contains(item) {
                list.append(item)
            }
        }
        return list.joined(separator: ",")
    }

    var translationProvider: TranslationProvider {
        get {
            _ = settingsRevision
            return (try? appDatabase.setting(Self.translationProviderKey)).flatMap(TranslationProvider.init) ?? .deepL
        }
        set {
            save { try appDatabase.setSetting(Self.translationProviderKey, to: newValue.rawValue) }
            settingsRevision += 1
            PageTranslator.shared.configure(newValue)
        }
    }

    /// Characters sent for translation this month, for services that don't count them.
    var translatedCharactersThisMonth: Int {
        _ = settingsRevision
        return (try? appDatabase.setting(Self.translatedCharactersKey(for: Date()))).flatMap { Int($0) } ?? 0
    }

    private func recordTranslatedCharacters(_ count: Int) {
        let total = translatedCharactersThisMonth + count
        save { try appDatabase.setSetting(Self.translatedCharactersKey(for: Date()), to: String(total)) }
        settingsRevision += 1
    }

    private static func translatedCharactersKey(for date: Date) -> String {
        let month = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(translatedCharactersKey) \(month.year ?? 0)-\(month.month ?? 0)"
    }

    var isDeveloperModeOnSelectedTab: Bool {
        selectedTab.map { isDeveloperMode(for: $0.url) } ?? false
    }

    func setDeveloperMode(_ isOn: Bool, for url: String) {
        guard let host = URL(string: url)?.host() else { return }
        var sites = loadSet(key: Self.developerSitesKey, profile: selectedSpace.profileFolder)
        if isOn { sites.insert(host) } else { sites.remove(host) }
        saveSet(sites, key: Self.developerSitesKey, profile: selectedSpace.profileFolder)
    }

    private func loadSet(key: String, profile folder: URL) -> Set<String> {
        guard let json = try? appDatabase.setting("\(key) \(folder.lastPathComponent)"),
              let values = try? JSONDecoder().decode([String].self, from: Data(json.utf8)) else { return [] }
        return Set(values)
    }

    private func saveSet(_ values: Set<String>, key: String, profile folder: URL) {
        let json = values.isEmpty ? nil : (try? JSONEncoder().encode(values.sorted())).flatMap { String(data: $0, encoding: .utf8) }
        save { try appDatabase.setSetting("\(key) \(folder.lastPathComponent)", to: json) }
        settingsRevision += 1
    }

    func profile(ofSpace id: UUID) -> FLXProfile? {
        profiles[id]
    }

    func favicon(for url: String, inSpace id: UUID) -> NSImage? {
        faviconCaches[id]?.image(for: url)
    }

    // Archive. Today's tabs go there when closed, or when left unseen longer than the profile's
    // archive delay.

    func archiveDelay(forProfile folder: URL) -> ArchiveDelay {
        (try? appDatabase.setting(Self.archiveDelayKey(forProfile: folder))).flatMap(ArchiveDelay.init) ?? .standard
    }

    func setArchiveDelay(_ delay: ArchiveDelay, forProfile folder: URL) {
        save { try appDatabase.setSetting(Self.archiveDelayKey(forProfile: folder), to: delay.rawValue) }
        archiveInactiveTabs()
    }

    private static func archiveDelayKey(forProfile folder: URL) -> String {
        "\(archiveDelayKey) \(folder.lastPathComponent)"
    }

    /// Archives inactive tabs now, then every 15 minutes.
    func startArchiving() {
        archiveInactiveTabs()
        archiveTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.archiveInactiveTabs() }
        }
    }

    private func archiveInactiveTabs() {
        let now = Date()
        for space in spaces {
            save { try profileDatabases[space.id]?.deleteArchivedTabs(before: now.addingTimeInterval(-Self.archiveLifetime)) }
            guard let interval = archiveDelay(forProfile: space.profileFolder).interval else { continue }
            // The tabs of a split go together, when none of them was seen for that long.
            let inactive = tabs.filter { tab in
                let group = split(of: tab).map(panes(of:)) ?? [tab]
                return tab.spaceID == space.id && tab.node.section == .today
                    && !group.contains { $0.id == selectedTabIDs[space.id] }
                    && group.allSatisfy { ($0.node.lastActiveAt ?? $0.node.createdAt) < now.addingTimeInterval(-interval) }
            }
            inactive.forEach(remove)
        }
    }

    private func archive(_ tab: Tab) {
        guard !tab.url.isEmpty else { return }
        let archived = ArchivedTab(id: UUID(), spaceID: tab.spaceID, title: tab.title, url: tab.url, archivedAt: Date())
        save { try profileDatabases[tab.spaceID]?.archive(archived) }
        archiveRevision += 1
    }

    var archivedTabsInSelectedSpace: [ArchivedTab] {
        _ = archiveRevision
        return (try? profileDatabases[selectedSpaceID]?.archivedTabs(in: selectedSpaceID)) ?? []
    }

    /// Opens the tab again in Today and takes it out of the archive.
    func restore(_ archived: ArchivedTab) {
        newTab(url: archived.url, in: archived.spaceID)
        deleteFromArchive(archived)
    }

    func deleteFromArchive(_ archived: ArchivedTab) {
        save { try profileDatabases[archived.spaceID]?.deleteArchivedTab(id: archived.id) }
        archiveRevision += 1
    }

    func clearArchiveOfSelectedSpace() {
        save { try profileDatabases[selectedSpaceID]?.clearArchive(in: selectedSpaceID) }
        archiveRevision += 1
    }

    // Sidebar tree. Folders only exist among favorites.

    @MainActor
    enum SidebarEntry {
        case tab(Tab)
        case folder(Folder)
        case split(Split)

        var id: UUID {
            switch self {
            case .tab(let tab): tab.id
            case .folder(let folder): folder.id
            case .split(let split): split.id
            }
        }

        var node: SidebarNode {
            switch self {
            case .tab(let tab): tab.node
            case .folder(let folder): folder.node
            case .split(let split): split.node
            }
        }

        var object: NSObject {
            switch self {
            case .tab(let tab): tab
            case .folder(let folder): folder
            case .split(let split): split
            }
        }
    }

    func entries(in section: SidebarNode.Section, parentID: UUID?, spaceID: UUID? = nil) -> [SidebarEntry] {
        let spaceID = spaceID ?? selectedSpaceID
        let tabEntries = tabs
            .filter { $0.spaceID == spaceID && $0.node.section == section && $0.node.parentID == parentID }
            .map(SidebarEntry.tab)
        let folderEntries = folders
            .filter { $0.spaceID == spaceID && $0.node.section == section && $0.node.parentID == parentID }
            .map(SidebarEntry.folder)
        let splitEntries = splits
            .filter { $0.spaceID == spaceID && $0.node.section == section && $0.node.parentID == parentID }
            .map(SidebarEntry.split)
        return (tabEntries + folderEntries + splitEntries).sorted { $0.node.position < $1.node.position }
    }

    func entry(id: UUID) -> SidebarEntry? {
        if let tab = tabs.first(where: { $0.id == id }) { return .tab(tab) }
        if let folder = folders.first(where: { $0.id == id }) { return .folder(folder) }
        if let split = splits.first(where: { $0.id == id }) { return .split(split) }
        return nil
    }

    /// The pinned tabs shown as icons at the top of the sidebar.
    var pinnedTabs: [Tab] {
        entries(in: .pinned, parentID: nil).compactMap { entry in
            if case .tab(let tab) = entry { tab } else { nil }
        }
    }

    func pin(_ tab: Tab) {
        move(.tab(tab), to: .pinned, parentID: nil, index: nil)
    }

    func moveToFavorites(_ tab: Tab) {
        move(.tab(tab), to: .favorites, parentID: nil, index: nil)
    }

    func moveToToday(_ tab: Tab) {
        move(.tab(tab), to: .today, parentID: nil, index: nil)
    }

    /// ⌘D pins a tab to the top of the sidebar, or sends a pinned tab back to today's tabs.
    func togglePin(_ tab: Tab) {
        tab.isPinned ? moveToToday(tab) : pin(tab)
    }

    /// A top-level folder can hold folders two levels deep, no more.
    static let maxFolderDepth = 2
    /// Two rows of six, three of four or four of three tiles.
    static let maxPinnedTabs = 12

    func canMove(_ entry: SidebarEntry, to section: SidebarNode.Section, parentID: UUID?) -> Bool {
        guard section == .favorites || parentID == nil else { return false }
        if section == .pinned, case .folder = entry { return false }
        if section == .pinned, case .split = entry { return false }
        if section == .pinned, case .tab(let tab) = entry, !tab.isPinned, pinnedTabs.count >= Self.maxPinnedTabs {
            return false
        }
        if case .folder(let folder) = entry {
            return section == .favorites && !isDescendant(parentID, of: folder.id) && canPlace(folder, in: parentID)
        }
        return true
    }

    /// Whether a folder, with everything it contains, fits under `parentID`. A nil folder stands
    /// for a new, empty one.
    func canPlace(_ folder: Folder?, in parentID: UUID?) -> Bool {
        depth(of: parentID) + 1 + (folder.map(subfolderLevels) ?? 0) <= Self.maxFolderDepth
    }

    /// -1 for the top of the pinned section, 0 for a top-level folder.
    private func depth(of folderID: UUID?) -> Int {
        var depth = -1
        var current = folderID
        while let id = current {
            depth += 1
            current = folders.first { $0.id == id }?.node.parentID
        }
        return depth
    }

    private func subfolderLevels(_ folder: Folder) -> Int {
        let children = folders.filter { $0.node.parentID == folder.id }
        return children.map { 1 + subfolderLevels($0) }.max() ?? 0
    }

    /// Moves an entry before the item at `index` among the destination's children, or to the end
    /// when `index` is nil. Returns false when the move isn't allowed.
    @discardableResult
    func move(_ entry: SidebarEntry, to section: SidebarNode.Section, parentID: UUID?, index: Int?) -> Bool {
        guard canMove(entry, to: section, parentID: parentID) else { return false }

        let siblings = entries(in: section, parentID: parentID, spaceID: entry.node.spaceID).filter { $0.id != entry.id }
        let insertion = min(index ?? siblings.count, siblings.count)
        let before = insertion > 0 ? siblings[insertion - 1].node.position : nil
        let after = insertion < siblings.count ? siblings[insertion].node.position : nil
        let position = FractionalIndex.between(before, after)

        switch entry {
        case .tab(let tab):
            let split = split(of: tab)
            tab.place(section: section, parentID: parentID, position: position)
            save { try profileDatabases[tab.spaceID]?.save(tab.node) }
            if let split { dissolveIfNeeded(split) }
        case .folder(let folder):
            folder.place(parentID: parentID, position: position)
            save { try profileDatabases[folder.spaceID]?.save(folder.node) }
        case .split(let split):
            split.place(section: section, parentID: parentID, position: position)
            let panes = panes(of: split)
            for pane in panes {
                pane.place(section: section, parentID: split.id, position: pane.node.position)
            }
            save { try profileDatabases[split.spaceID]?.save([split.node] + panes.map(\.node)) }
        }
        sidebarRevision += 1
        return true
    }

    private func isDescendant(_ id: UUID?, of ancestorID: UUID) -> Bool {
        var current = id
        while let currentID = current {
            if currentID == ancestorID { return true }
            current = folders.first { $0.id == currentID }?.node.parentID
        }
        return false
    }

    @discardableResult
    func createFolder(parentID: UUID? = nil) -> Folder? {
        guard canPlace(nil, in: parentID) else { return nil }
        let last = entries(in: .favorites, parentID: parentID).last?.node.position
        let node = SidebarNode(
            id: UUID(), spaceID: selectedSpaceID, parentID: parentID, kind: .folder, section: .favorites,
            position: FractionalIndex.between(last, nil), title: String(localized: "New Folder"), url: nil, originalURL: nil,
            isExpanded: true, lastActiveAt: nil, createdAt: Date()
        )
        save { try profileDatabases[selectedSpaceID]?.save(node) }
        let folder = Folder(node: node)
        folders.append(folder)
        sidebarRevision += 1
        folder.isEditingTitle = true
        return folder
    }

    func rename(_ folder: Folder, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        folder.isEditingTitle = false
        guard !title.isEmpty else { return }
        folder.rename(title)
        save { try profileDatabases[folder.spaceID]?.save(folder.node) }
    }

    func setExpanded(_ folder: Folder, _ isExpanded: Bool) {
        guard folder.node.isExpanded != isExpanded else { return }
        folder.setExpanded(isExpanded)
        save { try profileDatabases[folder.spaceID]?.save(folder.node) }
    }

    /// The folder's content moves up to where the folder was, nothing is lost.
    func delete(_ folder: Folder) {
        let content = entries(in: .favorites, parentID: folder.id, spaceID: folder.spaceID)
        let siblings = entries(in: .favorites, parentID: folder.node.parentID, spaceID: folder.spaceID)
        var before = siblings.last { $0.node.position < folder.node.position }?.node.position
        let after = siblings.first { $0.node.position > folder.node.position }?.node.position
        var moved: [SidebarNode] = []
        for entry in content {
            let position = FractionalIndex.between(before, after)
            before = position
            switch entry {
            case .tab(let tab):
                tab.place(section: .favorites, parentID: folder.node.parentID, position: position)
                moved.append(tab.node)
            case .folder(let child):
                child.place(parentID: folder.node.parentID, position: position)
                moved.append(child.node)
            case .split(let split):
                split.place(section: .favorites, parentID: folder.node.parentID, position: position)
                moved.append(split.node)
            }
        }
        folders.removeAll { $0 === folder }
        save { try profileDatabases[folder.spaceID]?.save(moved) }
        save { try profileDatabases[folder.spaceID]?.delete(nodeID: folder.id) }
        sidebarRevision += 1
    }

    // Split view.

    static let maxSplitPanes = 4

    func split(of tab: Tab) -> Split? {
        guard let parentID = tab.node.parentID else { return nil }
        return splits.first { $0.id == parentID }
    }

    func panes(of split: Split) -> [Tab] {
        tabs.filter { $0.node.parentID == split.id }.sorted { $0.node.position < $1.node.position }
    }

    var selectedSplit: Split? {
        selectedTab.flatMap(split(of:))
    }

    /// The tabs in the page area: the selected one, or all of its split's.
    var shownTabs: [Tab] {
        if let split = selectedSplit { return panes(of: split) }
        return selectedTab.map { [$0] } ?? []
    }

    /// Whether the tab can join the selected tab in a split. Pinned tabs stay icons, they don't
    /// split.
    func canSplit(with tab: Tab) -> Bool {
        guard let selected = selectedTab, tab !== selected, tab.spaceID == selected.spaceID,
              !tab.isPinned, !selected.isPinned else { return false }
        guard let split = selectedSplit else { return true }
        return self.split(of: tab) !== split && panes(of: split).count < Self.maxSplitPanes
    }

    /// Whether a new pane can be added next to the selected tab.
    var canAddSplitPane: Bool {
        guard let selected = selectedTab, !selected.isPinned else { return false }
        return selectedSplit.map { panes(of: $0).count < Self.maxSplitPanes } ?? true
    }

    /// Adds the tab to the selected tab's split, or makes one of the two in the selected tab's place.
    /// The new pane goes right after the selected one, or right before it.
    func addToSplit(_ tab: Tab, after: Bool = true) {
        guard canSplit(with: tab), let selected = selectedTab else { return }
        let previousSplit = split(of: tab)
        let split: Split
        if let selectedSplit {
            split = selectedSplit
        } else {
            let node = SidebarNode(
                id: UUID(), spaceID: selected.spaceID, parentID: selected.node.parentID, kind: .split,
                section: selected.node.section, position: selected.node.position, title: "", url: nil,
                originalURL: nil, isExpanded: true, lastActiveAt: Date(), createdAt: Date()
            )
            save { try profileDatabases[node.spaceID]?.save(node) }
            split = Split(node: node)
            splits.append(split)
            selected.place(section: node.section, parentID: split.id, position: FractionalIndex.between(nil, nil))
        }
        let current = panes(of: split).filter { $0 !== tab }
        let anchor = current.firstIndex { $0 === selected } ?? current.count - 1
        let (before, next) = after
            ? (current[anchor].node.position, current.indices.contains(anchor + 1) ? current[anchor + 1].node.position : nil)
            : (anchor > 0 ? current[anchor - 1].node.position : nil, current[anchor].node.position)
        tab.place(section: split.node.section, parentID: split.id, position: FractionalIndex.between(before, next))
        let panes = panes(of: split)
        // A new pane starts with an equal part.
        for pane in panes {
            pane.setShare(nil)
            if pane.emulation != nil { pane.toggleResponsive() }
        }
        save { try profileDatabases[split.spaceID]?.save(panes.map(\.node)) }
        if let previousSplit { dissolveIfNeeded(previousSplit) }
        sidebarRevision += 1
        select(tab)
    }

    func canDrop(_ tab: Tab, on target: SplitDropTarget) -> Bool {
        switch target {
        case .insert(let pane, _, _):
            let split = split(of: pane)
            guard tab !== pane, tab.spaceID == pane.spaceID, !tab.isPinned, !pane.isPinned,
                  split == nil || self.split(of: tab) !== split else { return false }
            return split.map { panes(of: $0).count < Self.maxSplitPanes } ?? true
        case .replace(let pane):
            // On a single page it would only show the tab, which a click in the sidebar does.
            guard let split = split(of: pane) else { return false }
            return tab !== pane && tab.spaceID == pane.spaceID && !tab.isPinned && self.split(of: tab) !== split
        }
    }

    func drop(_ tab: Tab, on target: SplitDropTarget) {
        guard canDrop(tab, on: target) else { return }
        switch target {
        case .insert(let pane, let after, let isVertical):
            let isNew = split(of: pane) == nil
            select(pane)
            addToSplit(tab, after: after)
            if isNew, let split = split(of: tab), split.isVertical != isVertical { toggleOrientation(split) }
        case .replace(let pane):
            replacePane(pane, with: tab)
        }
    }

    /// The tab takes the pane's place, and the pane's tab leaves the split.
    func replacePane(_ pane: Tab, with tab: Tab) {
        guard let split = split(of: pane) else { return }
        let previousSplit = self.split(of: tab)
        tab.place(section: split.node.section, parentID: split.id, position: pane.node.position)
        tab.setShare(pane.node.share)
        save { try profileDatabases[tab.spaceID]?.save(tab.node) }
        removeFromSplit(pane)
        if let previousSplit { dissolveIfNeeded(previousSplit) }
        sidebarRevision += 1
        select(tab)
    }

    /// Swaps the pane with the one before or after it.
    func movePane(_ tab: Tab, by offset: Int) {
        guard let split = split(of: tab) else { return }
        let panes = panes(of: split)
        guard let index = panes.firstIndex(where: { $0 === tab }), panes.indices.contains(index + offset) else { return }
        let other = panes[index + offset]
        let position = tab.node.position
        tab.place(section: split.node.section, parentID: split.id, position: other.node.position)
        other.place(section: split.node.section, parentID: split.id, position: position)
        save { try profileDatabases[split.spaceID]?.save([tab.node, other.node]) }
        sidebarRevision += 1
    }

    /// The tab leaves its split and goes just after it.
    func removeFromSplit(_ tab: Tab) {
        guard let split = split(of: tab) else { return }
        let siblings = entries(in: split.node.section, parentID: split.node.parentID, spaceID: split.spaceID)
        let after = siblings.first { $0.node.position > split.node.position }?.node.position
        tab.place(section: split.node.section, parentID: split.node.parentID, position: FractionalIndex.between(split.node.position, after))
        tab.setShare(nil)
        save { try profileDatabases[tab.spaceID]?.save(tab.node) }
        dissolveIfNeeded(split)
        sidebarRevision += 1
        if let pane = panes(of: split).first, selectedTab === tab { select(pane) }
    }

    /// Closes the pane's tab, or takes a kept tab out of the split: closing it would only unload it.
    func closePane(_ tab: Tab) {
        if tab.isKept {
            removeFromSplit(tab)
        } else {
            close(tab)
        }
    }

    /// Every tab takes the split's place, in pane order.
    func separate(_ split: Split) {
        let siblings = entries(in: split.node.section, parentID: split.node.parentID, spaceID: split.spaceID)
        var before = siblings.last { $0.node.position < split.node.position }?.node.position
        let after = siblings.first { $0.node.position > split.node.position }?.node.position
        let panes = panes(of: split)
        for pane in panes {
            let position = FractionalIndex.between(before, after)
            before = position
            pane.place(section: split.node.section, parentID: split.node.parentID, position: position)
            pane.setShare(nil)
        }
        save { try profileDatabases[split.spaceID]?.save(panes.map(\.node)) }
        delete(split)
        sidebarRevision += 1
    }

    func toggleOrientation(_ split: Split) {
        split.setVertical(!split.isVertical)
        save { try profileDatabases[split.spaceID]?.save(split.node) }
    }

    /// `shares` are in pane order and add up to 1.
    func setShares(_ shares: [Double], of split: Split) {
        let panes = panes(of: split)
        guard panes.count == shares.count else { return }
        for (pane, share) in zip(panes, shares) {
            pane.setShare(share)
        }
        save { try profileDatabases[split.spaceID]?.save(panes.map(\.node)) }
    }

    /// A split of one tab is no split: the tab takes its place.
    private func dissolveIfNeeded(_ split: Split) {
        let panes = panes(of: split)
        guard panes.count < 2 else { return }
        if let last = panes.first {
            last.place(section: split.node.section, parentID: split.node.parentID, position: split.node.position)
            last.setShare(nil)
            save { try profileDatabases[split.spaceID]?.save(last.node) }
        }
        delete(split)
    }

    /// The node's children are deleted with it, so the tabs must have left it first.
    private func delete(_ split: Split) {
        splits.removeAll { $0 === split }
        save { try profileDatabases[split.spaceID]?.delete(nodeID: split.id) }
    }

    // Import from other browsers.

    /// Each space goes to a new space, or into an existing one when `destinations` names it.
    /// Spaces sharing a profile give new spaces sharing one too, and each space keeps the
    /// extensions it had, to install them again.
    func importSpaces(_ imported: [ImportedSpace], from source: ImportSource, destinations: [String: UUID], includesToday: Bool) {
        var spaceByProfile: [URL: UUID] = [:]
        var favicons: [URL: any SiteIcons] = [:]
        defer { favicons.values.forEach { $0.close() } }
        var shownSpace: UUID?
        let lastSpace = source.lastSpaceID
        for space in imported {
            // A new profile gets the browser's history, passwords and sign-ins. An open one can't.
            let spaceID = destinations[space.id] ?? createSpace(
                name: space.name, icon: space.icon, color: space.color ?? Self.spaceColors[0],
                sharingProfileOf: spaceByProfile[space.profileFolder]
            ) { folder in
                source.prepare(folder, from: space.profileFolder)
            }
            if spaceByProfile[space.profileFolder] == nil {
                spaceByProfile[space.profileFolder] = spaceID
            }
            if shownSpace == nil || space.id == lastSpace { shownSpace = spaceID }
            if source.isChromium {
                addImportedExtensions(ImportedExtension.installed(inProfile: space.profileFolder), to: spaceID)
            }
            if source.exportsPasswords { setPasswordExport(from: source, in: spaceID) }
            let icons = favicons[space.profileFolder] ?? source.siteIcons(in: space.profileFolder)
            favicons[space.profileFolder] = icons

            var importer = SidebarImporter(spaceID: spaceID, favicons: icons, cache: faviconCaches[spaceID])
            // The grid takes twelve tabs: the others go first among favorites.
            let pinned = space.pinned.flatMap(\.tabs)
            let room = max(Self.maxPinnedTabs - pinnedTabs(in: spaceID).count, 0)
            importer.add(pinned.prefix(room).map(ImportedItem.tab), section: .pinned, after: entries(in: .pinned, parentID: nil, spaceID: spaceID).last?.node.position)
            importer.add(pinned.dropFirst(room).map(ImportedItem.tab) + space.favorites, section: .favorites,
                         after: entries(in: .favorites, parentID: nil, spaceID: spaceID).last?.node.position)
            if includesToday {
                importer.add(space.today, section: .today, after: entries(in: .today, parentID: nil, spaceID: spaceID).last?.node.position)
            }
            save { try profileDatabases[spaceID]?.save(importer.nodes) }
            for node in importer.nodes {
                switch node.kind {
                case .tab: tabs.append(makeTab(node))
                case .folder: folders.append(Folder(node: node))
                case .split: splits.append(Split(node: node))
                }
            }
        }
        sidebarRevision += 1
        // The space the browser showed last, rather than its first one.
        if let shownSpace { selectedSpaceID = shownSpace }
    }

    func importedExtensions(in spaceID: UUID) -> [ImportedExtension] {
        _ = settingsRevision
        return (try? appDatabase.setting("\(Self.importedExtensionsKey) \(spaceID)"))
            .flatMap { try? JSONDecoder().decode([ImportedExtension].self, from: Data($0.utf8)) } ?? []
    }

    private func addImportedExtensions(_ extensions: [ImportedExtension], to spaceID: UUID) {
        let current = importedExtensions(in: spaceID)
        let all = current + extensions.filter { item in !current.contains { $0.id == item.id } }
        guard all.count > current.count, let data = try? JSONEncoder().encode(all) else { return }
        save { try appDatabase.setSetting("\(Self.importedExtensionsKey) \(spaceID)", to: String(decoding: data, as: UTF8.self)) }
        settingsRevision += 1
    }

    /// The browser whose passwords the space is waiting for, as a file the user exports.
    func passwordExport(in spaceID: UUID) -> String? {
        _ = settingsRevision
        return try? appDatabase.setting("\(Self.passwordExportKey) \(spaceID)")
    }

    private func setPasswordExport(from source: ImportSource, in spaceID: UUID) {
        save { try appDatabase.setSetting("\(Self.passwordExportKey) \(spaceID)", to: source.name) }
        settingsRevision += 1
    }

    func hidePasswordExport(in spaceID: UUID) {
        save { try appDatabase.setSetting("\(Self.passwordExportKey) \(spaceID)", to: nil) }
        settingsRevision += 1
    }

    func isImportedExtensionsCardHidden(in spaceID: UUID) -> Bool {
        _ = settingsRevision
        return (try? appDatabase.setting("\(Self.importedExtensionsCardHiddenKey) \(spaceID)")) == "true"
    }

    func hideImportedExtensionsCard(in spaceID: UUID) {
        save { try appDatabase.setSetting("\(Self.importedExtensionsCardHiddenKey) \(spaceID)", to: "true") }
        settingsRevision += 1
    }

    /// Extensions keep their Chrome Web Store id once installed.
    func isExtensionInstalled(_ id: String, in spaceID: UUID) -> Bool {
        guard let space = spaces.first(where: { $0.id == spaceID }) else { return false }
        return extensionList(forProfile: space.profileFolder)?.extensions.contains { $0.id == id } ?? false
    }

    private func pinnedTabs(in spaceID: UUID) -> [Tab] {
        tabs.filter { $0.spaceID == spaceID && $0.node.section == .pinned && $0.node.parentID == nil }
    }

    func openSelectedTabInChromeWindow() {
        guard let tab = selectedTab else { return }
        selectedProfile.showChromeWindow(withURL: tab.url, title: "Chrome - \(selectedSpace.name)")
    }

    /// Chromium's extension manager, in a tab of the selected space: each space has its own.
    func showExtensionsOfSelectedSpace() {
        showChromePage("chrome://extensions")
    }

    /// Chromium's password manager, which keeps the selected space's passwords on this Mac.
    func showPasswordsOfSelectedSpace() {
        showChromePage("chrome://password-manager")
    }

    var historyOfSelectedSpace: ChromiumHistory? {
        histories[selectedSpaceID]
    }

    func favicon(for url: String) -> NSImage? {
        faviconCaches[selectedSpaceID]?.image(for: url)
    }

    func showHistoryOfSelectedSpace() {
        showChromePage("chrome://history")
    }

    func showClearBrowsingDataOfSelectedSpace() {
        showChromePage("chrome://settings/clearBrowserData")
    }

    /// Shows one of Chromium's pages for a profile in a space using it, the selected one if it does.
    func showChromePage(_ url: String, forProfile folder: URL) {
        let candidates = spaces.filter { $0.profileFolder.standardizedFileURL == folder.standardizedFileURL }
        guard let space = candidates.first(where: { $0.id == selectedSpaceID }) ?? candidates.first else { return }
        selectedSpaceID = space.id
        showChromePage(url)
    }

    /// Selects the space's tab already showing the page, or opens one.
    private func showChromePage(_ url: String) {
        if let tab = tabsInSelectedSpace.first(where: { $0.url.hasPrefix(url) }) {
            select(tab)
        } else {
            newTab(url: url)
        }
    }

    /// Opens a page Chromium wanted to show in a window of its own, as a tab of a space using that
    /// profile, the selected one if it does.
    func openExternalPage(_ url: String, profilePath: String) {
        let folder = URL(filePath: profilePath).standardizedFileURL
        let candidates = spaces.filter { $0.profileFolder.standardizedFileURL == folder }
        guard let space = candidates.first(where: { $0.id == selectedSpaceID }) ?? candidates.first else { return }
        selectedSpaceID = space.id
        newTab(url: url, in: space.id)
    }

    /// Whether typed text is meant as an address rather than a search.
    static func looksLikeURL(_ text: String) -> Bool {
        if text.contains("://") || text.hasPrefix("about:") {
            return true
        }
        return !text.contains(" ") && (text.contains(".") || text.hasPrefix("localhost"))
    }

    static func normalizedURL(_ text: String) -> String {
        if text.contains("://") || text.hasPrefix("about:") {
            return text
        }
        return (text.hasPrefix("localhost") ? "http://" : "https://") + text
    }

    /// Storage errors are logged rather than shown: the session goes on in memory.
    private func save(_ write: () throws -> Void) {
        do {
            try write()
        } catch {
            Self.logger.error("Saving failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
