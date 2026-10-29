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
    private static let logger = Logger(subsystem: "com.flux-browser.Flux", category: "storage")

    private(set) var spaces: [Space] = []
    private(set) var tabs: [Tab] = []
    private(set) var folders: [Folder] = []
    /// Bumped whenever the sidebar's structure changes: items added, removed or moved.
    private(set) var sidebarRevision = 0
    /// Each space's selected tab, saved in its space record as well.
    private var selectedTabIDs: [UUID: UUID] = [:]
    var selectedSpaceID: UUID {
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

    init(appDatabase: AppDatabase) throws {
        self.appDatabase = appDatabase
        var records = try appDatabase.spaces()
        if records.isEmpty {
            records = try Self.createFirstSpaces(in: appDatabase)
        }
        let savedSelection = try appDatabase.setting(Self.selectedSpaceKey).flatMap(UUID.init(uuidString:))
        selectedSpaceID = records.first { $0.id == savedSelection }?.id ?? records[0].id

        for record in records {
            try open(record)
        }
    }

    /// Personal and Work, with the profile folders of the first prototype so existing sign-ins stay.
    private static func createFirstSpaces(in database: AppDatabase) throws -> [SpaceRecord] {
        let first = [
            ("6F1C2B7E-3D4A-4C1E-9B2F-1A2B3C4D5E01", "Personal", "#F97316"),
            ("6F1C2B7E-3D4A-4C1E-9B2F-1A2B3C4D5E02", "Work", "#3B82F6"),
        ]
        var position: String?
        return try first.map { id, name, color in
            position = FractionalIndex.between(position, nil)
            let record = SpaceRecord(
                id: UUID(uuidString: id)!, name: name, icon: nil, color: color, position: position!,
                profileFolder: "Space \(id)", selectedTabID: nil, createdAt: Date()
            )
            try database.save(record)
            return record
        }
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

        let nodes = try database.nodes(in: space.id)
        for node in nodes {
            switch node.kind {
            case .tab: tabs.append(makeTab(node))
            case .folder: folders.append(Folder(node: node))
            }
        }
    }

    private func makeTab(_ node: SidebarNode, page: FLXBrowserView? = nil) -> Tab {
        let tab = Tab(node: node, profile: profiles[node.spaceID]!, favicons: faviconCaches[node.spaceID]!, page: page)
        tab.onChange = { [weak self] tab in
            self?.save { try self?.profileDatabases[tab.spaceID]?.save(tab.node) }
        }
        tab.onOpenPage = { [weak self] opener, page, background in
            self?.newTab(url: page.currentURL, in: opener.spaceID, page: page, selecting: !background)
        }
        return tab
    }

    /// A new space gets a profile of its own, so nothing is shared with other spaces.
    func createSpace(name: String, icon: String?, color: String) {
        let id = UUID()
        let lastPosition = spaces.last.flatMap { spaceRecords[$0.id]?.position }
        let record = SpaceRecord(
            id: id, name: name, icon: icon, color: color,
            position: FractionalIndex.between(lastPosition, nil),
            profileFolder: "Profile \(id.uuidString)", selectedTabID: nil, createdAt: Date()
        )
        save { try appDatabase.save(record) }
        save { try open(record) }
        selectedSpaceID = id
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
        sidebarRevision += 1
        if selectedSpaceID == id {
            selectedSpaceID = spaces[0].id
        }

        save { try appDatabase.delete(record) }
        if ownsProfile {
            save { try appDatabase.scheduleDeletion(ofProfileFolder: record.profileFolder) }
        } else {
            save { try database?.deleteNodes(in: id) }
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

    private func close(_ tab: Tab, removing: Bool) {
        let wasSelected = selectedTab?.id == tab.id
        if !removing {
            tab.unload()
        } else {
            tabs.removeAll { $0 === tab }
            tab.close()
            save { try profileDatabases[tab.spaceID]?.delete(nodeID: tab.id) }
            sidebarRevision += 1
        }
        if wasSelected {
            let candidates = tabs.filter { $0.spaceID == tab.spaceID && $0 !== tab && ($0.isLoaded || !$0.isKept) }
            if let next = candidates.max(by: { ($0.node.lastActiveAt ?? .distantPast) < ($1.node.lastActiveAt ?? .distantPast) }) {
                select(next)
            } else {
                selectedTabIDs[tab.spaceID] = nil
            }
        }
    }

    // Sidebar tree. Folders only exist among favorites.

    @MainActor
    enum SidebarEntry {
        case tab(Tab)
        case folder(Folder)

        var id: UUID {
            switch self {
            case .tab(let tab): tab.id
            case .folder(let folder): folder.id
            }
        }

        var node: SidebarNode {
            switch self {
            case .tab(let tab): tab.node
            case .folder(let folder): folder.node
            }
        }

        var object: NSObject {
            switch self {
            case .tab(let tab): tab
            case .folder(let folder): folder
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
        return (tabEntries + folderEntries).sorted { $0.node.position < $1.node.position }
    }

    func entry(id: UUID) -> SidebarEntry? {
        if let tab = tabs.first(where: { $0.id == id }) { return .tab(tab) }
        if let folder = folders.first(where: { $0.id == id }) { return .folder(folder) }
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
            tab.place(section: section, parentID: parentID, position: position)
            save { try profileDatabases[tab.spaceID]?.save(tab.node) }
        case .folder(let folder):
            folder.place(parentID: parentID, position: position)
            save { try profileDatabases[folder.spaceID]?.save(folder.node) }
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
            position: FractionalIndex.between(last, nil), title: "New Folder", url: nil, originalURL: nil,
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
            }
        }
        folders.removeAll { $0 === folder }
        save { try profileDatabases[folder.spaceID]?.save(moved) }
        save { try profileDatabases[folder.spaceID]?.delete(nodeID: folder.id) }
        sidebarRevision += 1
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
