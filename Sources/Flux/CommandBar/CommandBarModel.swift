import AppKit
import Observation

/// What the command bar offers for the text typed so far, in the selected space only.
@MainActor
@Observable
final class CommandBarModel {
    enum Target: Equatable {
        /// Opens pages in a new tab. Nothing is created until a suggestion is chosen.
        case newTab
        /// Loads pages in the selected tab. The bar starts with its URL.
        case selectedTab
        /// Opens pages in a new pane of the selected tab's split, or of a split made with it, after
        /// the selected pane or before it.
        case splitPane(after: Bool)
    }

    enum Suggestion: Identifiable {
        case tab(Tab)
        case page(ChromiumHistory.Page)
        /// The home page of a site whose domain starts with the text.
        case site(ChromiumHistory.Page)
        case url(String)
        case search(String)

        var id: String {
            switch self {
            case .tab(let tab): "tab:\(tab.id)"
            case .page(let page): "page:\(page.url)"
            case .site(let page): "site:\(page.url)"
            case .url(let url): "url:\(url)"
            case .search(let query): "search:\(query)"
            }
        }
    }

    static let maximumSuggestions = 7

    let target: Target
    var query: String {
        didSet { refresh() }
    }
    private(set) var suggestions: [Suggestion] = []
    private(set) var selectedIndex = 0
    var onFinish: (() -> Void)?
    private var historySearch: Task<Void, Never>?

    let state: BrowserState

    init(state: BrowserState, target: Target) {
        self.state = state
        self.target = target
        query = target == .selectedTab ? state.selectedTab?.url ?? "" : ""
        refresh()
    }

    func moveSelection(by offset: Int) {
        guard !suggestions.isEmpty else { return }
        selectedIndex = (selectedIndex + offset + suggestions.count) % suggestions.count
    }

    func select(_ index: Int) {
        guard suggestions.indices.contains(index) else { return }
        selectedIndex = index
    }

    func favicon(for suggestion: Suggestion) -> NSImage? {
        guard case .page(let page) = suggestion else { return nil }
        return state.favicon(for: page.url)
    }

    /// In the background, a new tab opens without being selected.
    func performSelected(inBackground background: Bool = false) {
        guard suggestions.indices.contains(selectedIndex) else { return }
        switch suggestions[selectedIndex] {
        case .tab(let tab):
            if case .splitPane(let after) = target, state.canSplit(with: tab) {
                state.addToSplit(tab, after: after)
            } else {
                state.select(tab)
            }
        case .page(let page), .site(let page):
            open(page.url, inBackground: background)
        case .url(let url):
            open(url, inBackground: background)
        case .search(let text):
            open(state.searchEngine.url(for: text), inBackground: background)
        }
        onFinish?()
    }

    private func open(_ url: String, inBackground background: Bool) {
        switch target {
        case .selectedTab:
            if let tab = state.selectedTab {
                tab.load(url)
            } else {
                state.newTab(url: url, selecting: !background)
            }
        case .splitPane(let after):
            state.addToSplit(state.newTab(url: url, selecting: false), after: after)
        case .newTab:
            state.newTab(url: url, selecting: !background)
        }
    }

    /// Open tabs show at once. History pages are added when the search returns, unless the text
    /// changed meanwhile.
    private func refresh() {
        historySearch?.cancel()
        suggestions = suggestions(for: query, pages: [])
        selectedIndex = 0
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let history = state.historyOfSelectedSpace else { return }
        historySearch = Task { [weak self, query] in
            let pages = await history.search(text, limit: Self.maximumSuggestions)
            let site = await history.site(startingWith: text)
            guard let self, !Task.isCancelled, self.query == query else { return }
            let selected = self.suggestions.indices.contains(self.selectedIndex) ? self.suggestions[self.selectedIndex].id : nil
            self.suggestions = self.suggestions(for: query, pages: pages, site: site)
            // Keeps the row picked with the arrow keys while the search ran.
            self.selectedIndex = self.suggestions.firstIndex { $0.id == selected } ?? 0
        }
    }

    private func suggestions(for query: String, pages: [ChromiumHistory.Page], site: ChromiumHistory.Page? = nil) -> [Suggestion] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let tabs = state.tabsInSelectedSpace.filter { $0 !== state.selectedTab }

        guard !text.isEmpty else {
            let recent = tabs.sorted { ($0.node.lastActiveAt ?? .distantPast) > ($1.node.lastActiveAt ?? .distantPast) }
            return recent.prefix(Self.maximumSuggestions).map(Suggestion.tab)
        }

        let matches = tabs.filter { $0.title.localizedStandardContains(text) || $0.url.localizedStandardContains(text) }
        // A tab whose title or site starts with the text is most likely the one wanted, as in Arc.
        let best = matches.first { tab in
            tab.title.range(of: text, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
                || (URL(string: tab.url)?.host() ?? "").replacingOccurrences(of: "www.", with: "")
                    .range(of: text, options: [.anchored, .caseInsensitive]) != nil
        }
        let openKeys = Set(state.tabsInSelectedSpace.map { ChromiumHistory.pageKey($0.url) })
        let isOpen = { (page: ChromiumHistory.Page) in openKeys.contains(ChromiumHistory.pageKey(page.url)) }
        // The home page of a site whose domain starts with the text comes first, as in Chromium's
        // address bar.
        let home = site.flatMap { isOpen($0) ? nil : $0 }
        let newPages = pages.filter { !isOpen($0) && ChromiumHistory.pageKey($0.url) != home.map { ChromiumHistory.pageKey($0.url) } }
        // A history page only goes before the typed text when its site or title starts with it,
        // so typing a search and pressing return still searches.
        let bestPage = best == nil ? home ?? newPages.first { ChromiumHistory.startsMatch($0, text: text) } : nil

        var typed: [Suggestion] = [.search(text)]
        if BrowserState.looksLikeURL(text) {
            let url = BrowserState.normalizedURL(text)
            // Typing a domain in full gives its home page above, which already opens it.
            let isHome = [bestPage, home].contains { page in
                page.map { ChromiumHistory.site(of: $0.url) == ChromiumHistory.site(of: url) } == true
            }
            if !isHome { typed.insert(.url(url), at: 0) }
        }

        var list: [Suggestion] = []
        if let best { list.append(.tab(best)) }
        if let bestPage { list.append(bestPage == home ? .site(bestPage) : .page(bestPage)) }
        list += typed
        list += matches.filter { $0 !== best }.map(Suggestion.tab)
        list += newPages.filter { $0 != bestPage }.map(Suggestion.page)
        return Array(list.prefix(Self.maximumSuggestions))
    }
}
