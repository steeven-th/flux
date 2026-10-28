import Foundation
import Observation

@MainActor
@Observable
final class BrowserState {
    static let newTabURL = "https://www.google.com"

    let spaces: [Space]
    private(set) var tabs: [Tab] = []
    var selectedSpaceID: UUID
    private var selectedTabIDs: [UUID: UUID] = [:]
    @ObservationIgnored private var profiles: [UUID: FLXProfile] = [:]

    init(spaces: [Space]) {
        self.spaces = spaces
        selectedSpaceID = spaces[0].id
        for space in spaces {
            profiles[space.id] = FLXProfile(atPath: AppPaths.profileFolder(for: space.id).path)
            newTab(url: "https://accounts.google.com", in: space.id)
        }
    }

    var selectedSpace: Space {
        spaces.first { $0.id == selectedSpaceID } ?? spaces[0]
    }

    var tabsInSelectedSpace: [Tab] {
        tabs.filter { $0.spaceID == selectedSpaceID }
    }

    var selectedTab: Tab? {
        guard let id = selectedTabIDs[selectedSpaceID] else { return nil }
        return tabs.first { $0.id == id }
    }

    func select(_ tab: Tab) {
        selectedTabIDs[tab.spaceID] = tab.id
    }

    @discardableResult
    func newTab(url: String = BrowserState.newTabURL, in spaceID: UUID? = nil) -> Tab {
        let spaceID = spaceID ?? selectedSpaceID
        let tab = Tab(url: url, spaceID: spaceID, profile: profiles[spaceID]!)
        tabs.append(tab)
        select(tab)
        return tab
    }

    func close(_ tab: Tab) {
        guard let index = tabs.firstIndex(of: tab) else { return }
        tabs.remove(at: index)
        tab.browserView.close()
        if selectedTabIDs[tab.spaceID] == tab.id {
            selectedTabIDs[tab.spaceID] = tabs.last { $0.spaceID == tab.spaceID }?.id
        }
    }

    func showExtensionsOfSelectedSpace() {
        profiles[selectedSpaceID]?.showExtensionsWindow(withTitle: "Extensions - \(selectedSpace.name)")
    }

    /// Opens a page Chromium wanted to show in a window of its own, as a tab of the space that uses
    /// the same profile.
    func openExternalPage(_ url: String, profilePath: String) {
        let profileFolder = URL(filePath: profilePath).standardizedFileURL
        guard let space = spaces.first(where: {
            AppPaths.profileFolder(for: $0.id).standardizedFileURL == profileFolder
        }) else { return }
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
}
