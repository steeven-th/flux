import Foundation

/// The pages before and after a tab's page, kept so Back and Forward still work after Flux
/// restarted or the tab was unloaded. CEF can't give a new page Chromium's history back, so Flux
/// keeps the pages Chromium no longer knows and loads them again when the tab goes there.
struct NavigationHistory: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var url: String
        var title: String
    }

    /// Oldest first.
    var back: [Entry] = []
    var forward: [Entry] = []

    static let limit = 50

    var isEmpty: Bool {
        back.isEmpty && forward.isEmpty
    }

    func limited() -> NavigationHistory {
        NavigationHistory(back: Array(back.suffix(Self.limit)), forward: Array(forward.prefix(Self.limit)))
    }
}

/// Chromium's history of a page, as `Page.getNavigationHistory` gives it.
struct PageNavigationEntries {
    struct Entry {
        let id: Int
        let url: String
        let title: String

        var saved: NavigationHistory.Entry {
            NavigationHistory.Entry(url: url, title: title)
        }
    }

    let entries: [Entry]
    let currentIndex: Int

    init?(_ result: [String: Any]?) {
        guard let result, let index = result["currentIndex"] as? Int,
              let entries = result["entries"] as? [[String: Any]] else { return nil }
        self.entries = entries.compactMap { entry in
            guard let id = entry["id"] as? Int, let url = entry["url"] as? String else { return nil }
            return Entry(id: id, url: url, title: entry["title"] as? String ?? "")
        }
        guard self.entries.count == entries.count, self.entries.indices.contains(index) else { return nil }
        currentIndex = index
    }

    var back: [NavigationHistory.Entry] {
        entries[..<currentIndex].map { $0.saved }
    }

    var forward: [NavigationHistory.Entry] {
        entries[(currentIndex + 1)...].map { $0.saved }
    }

    /// The current page, then the ones after it.
    var fromCurrent: [NavigationHistory.Entry] {
        entries[currentIndex...].map { $0.saved }
    }

    /// The pages up to the current one.
    var upToCurrent: [NavigationHistory.Entry] {
        entries[...currentIndex].map { $0.saved }
    }
}
