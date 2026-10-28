import Foundation
import Observation
import os

@MainActor
@Observable
final class BrowserState {
    static let newTabURL = "https://www.google.com"
    static let spaceColors = ["#F97316", "#3B82F6", "#22C55E", "#A855F7", "#EC4899", "#EAB308", "#14B8A6", "#EF4444"]
    private static let selectedSpaceKey = "selectedSpaceID"
    private static let logger = Logger(subsystem: "com.flux-browser.Flux", category: "storage")

    private(set) var spaces: [Space] = []
    private(set) var tabs: [Tab] = []
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
        extensionLists[space.id] = ExtensionList(profileFolder: space.profileFolder)

        let restored = try database.nodes(in: space.id).filter { $0.section == .today && $0.kind == .tab }
        for node in restored {
            tabs.append(makeTab(node, profile: profile))
        }
        if restored.isEmpty {
            newTab(in: space.id)
        }
    }

    private func makeTab(_ node: SidebarNode, profile: FLXProfile) -> Tab {
        let tab = Tab(node: node, profile: profile)
        tab.onChange = { [weak self] tab in
            self?.save { try self?.profileDatabases[tab.spaceID]?.save(tab.node) }
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
    func newTab(url: String = BrowserState.newTabURL, in spaceID: UUID? = nil) -> Tab {
        let spaceID = spaceID ?? selectedSpaceID
        let last = tabs.last { $0.spaceID == spaceID }?.node.position
        let node = SidebarNode(
            id: UUID(), spaceID: spaceID, parentID: nil, kind: .tab, section: .today,
            position: FractionalIndex.between(last, nil), title: "", url: url,
            lastActiveAt: Date(), createdAt: Date()
        )
        save { try profileDatabases[spaceID]?.save(node) }
        let tab = makeTab(node, profile: profiles[spaceID]!)
        tabs.append(tab)
        select(tab)
        return tab
    }

    func close(_ tab: Tab) {
        guard let index = tabs.firstIndex(of: tab) else { return }
        let wasSelected = selectedTab?.id == tab.id
        tabs.remove(at: index)
        tab.close()
        save { try profileDatabases[tab.spaceID]?.delete(nodeID: tab.id) }
        if wasSelected, let next = tabs.last(where: { $0.spaceID == tab.spaceID }) {
            select(next)
        }
    }

    func openSelectedTabInChromeWindow() {
        guard let tab = selectedTab else { return }
        selectedProfile.showChromeWindow(withURL: tab.url, title: "Chrome - \(selectedSpace.name)")
    }

    func showExtensionsOfSelectedSpace() {
        selectedProfile.showExtensionsWindow(withTitle: "Extensions - \(selectedSpace.name)")
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

    /// Opens what was typed in the address field: a URL when it looks like one, a search otherwise.
    func open(_ input: String) {
        let url = Self.url(for: input)
        if let tab = selectedTab {
            tab.load(url)
        } else {
            newTab(url: url)
        }
    }

    static func url(for input: String) -> String {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.contains("://") {
            return text
        }
        if !text.contains(" "), text.contains(".") || text.hasPrefix("localhost") {
            return "https://" + text
        }
        let query = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        return "https://www.google.com/search?q=" + query
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
