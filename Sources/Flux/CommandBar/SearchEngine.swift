import Foundation

struct SearchEngine: Hashable, Identifiable {
    let id: String
    let name: String
    /// The search URL, with `%s` where the query goes.
    let template: String

    static let google = SearchEngine(id: "google", name: "Google", template: "https://www.google.com/search?q=%s")

    static let all: [SearchEngine] = [
        google,
        SearchEngine(id: "duckduckgo", name: "DuckDuckGo", template: "https://duckduckgo.com/?q=%s"),
        SearchEngine(id: "bing", name: "Bing", template: "https://www.bing.com/search?q=%s"),
        SearchEngine(id: "ecosia", name: "Ecosia", template: "https://www.ecosia.org/search?q=%s"),
        SearchEngine(id: "qwant", name: "Qwant", template: "https://www.qwant.com/?q=%s"),
        SearchEngine(id: "kagi", name: "Kagi", template: "https://kagi.com/search?q=%s"),
    ]

    /// The stored setting is a known engine's id, or the template of a custom one.
    init(setting: String?) {
        if let setting, let known = Self.all.first(where: { $0.id == setting }) {
            self = known
        } else if let setting, setting.contains("%s") {
            self = SearchEngine(id: setting, name: URL(string: setting)?.host() ?? "Search", template: setting)
        } else {
            self = .google
        }
    }

    private init(id: String, name: String, template: String) {
        self.id = id
        self.name = name
        self.template = template
    }

    func url(for query: String) -> String {
        // urlQueryAllowed keeps & + = and #, which would cut the query short.
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=#?"))
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        return template.replacingOccurrences(of: "%s", with: encoded)
    }
}
