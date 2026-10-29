import AppKit
import Observation

/// What the command bar offers for the text typed so far, in the selected space only.
@MainActor
@Observable
final class CommandBarModel {
    enum Target {
        /// Opens pages in a new tab. Nothing is created until a suggestion is chosen.
        case newTab
        /// Loads pages in the selected tab. The bar starts with its URL.
        case selectedTab
    }

    enum Suggestion: Identifiable {
        case tab(Tab)
        case url(String)
        case search(String)

        var id: String {
            switch self {
            case .tab(let tab): "tab:\(tab.id)"
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

    /// In the background, a new tab opens without being selected.
    func performSelected(inBackground background: Bool = false) {
        guard suggestions.indices.contains(selectedIndex) else { return }
        switch suggestions[selectedIndex] {
        case .tab(let tab):
            state.select(tab)
        case .url(let url):
            open(url, inBackground: background)
        case .search(let text):
            open(state.searchEngine.url(for: text), inBackground: background)
        }
        onFinish?()
    }

    private func open(_ url: String, inBackground background: Bool) {
        if target == .selectedTab, let tab = state.selectedTab {
            tab.load(url)
        } else {
            state.newTab(url: url, selecting: !background)
        }
    }

    private func refresh() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let tabs = state.tabsInSelectedSpace.filter { $0 !== state.selectedTab }
        selectedIndex = 0

        guard !text.isEmpty else {
            let recent = tabs.sorted { ($0.node.lastActiveAt ?? .distantPast) > ($1.node.lastActiveAt ?? .distantPast) }
            suggestions = recent.prefix(Self.maximumSuggestions).map(Suggestion.tab)
            return
        }

        let typed: Suggestion = BrowserState.looksLikeURL(text) ? .url(BrowserState.normalizedURL(text)) : .search(text)
        let matches = tabs.filter { $0.title.localizedStandardContains(text) || $0.url.localizedStandardContains(text) }
        // A tab whose title or site starts with the text is most likely the one wanted, as in Arc.
        let best = matches.first { tab in
            tab.title.range(of: text, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
                || (URL(string: tab.url)?.host() ?? "").replacingOccurrences(of: "www.", with: "")
                    .range(of: text, options: [.anchored, .caseInsensitive]) != nil
        }
        var list: [Suggestion] = []
        if let best { list.append(.tab(best)) }
        list.append(typed)
        list += matches.filter { $0 !== best }.map(Suggestion.tab)
        suggestions = Array(list.prefix(Self.maximumSuggestions))
    }
}
