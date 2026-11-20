import Foundation

/// Where a live folder's tabs come from: a feed, or a GitHub search.
struct LiveSource: Codable, Hashable {
    enum Kind: String, Codable {
        case feed, github
    }

    var kind: Kind
    /// The feed's address, or the GitHub search, as typed on github.com/pulls.
    var value: String
    /// Items the user removed, which stay out when the folder updates.
    var dismissed: [String] = []

    /// At most this many tabs, the newest.
    static let maxItems = 25
    static let refreshInterval: TimeInterval = 30 * 60

    init(kind: Kind, value: String) {
        self.kind = kind
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        value = try container.decode(String.self, forKey: .value)
        dismissed = try container.decodeIfPresent([String].self, forKey: .dismissed) ?? []
    }

    mutating func dismiss(_ itemID: String) {
        dismissed = Array((dismissed + [itemID]).suffix(200))
    }
}

/// One page of a source, which becomes a tab.
struct LiveItem: Equatable {
    /// Stays the same when the item's title changes.
    let id: String
    let title: String
    let url: String
}

/// Searches offered for GitHub, which `@me` makes the signed-in user's.
enum GitHubSearch: String, CaseIterable, Identifiable {
    case reviewRequested = "is:open is:pr review-requested:@me archived:false"
    case myPullRequests = "is:open is:pr author:@me archived:false"
    case assignedIssues = "is:open is:issue assignee:@me archived:false"

    var id: Self { self }

    var name: LocalizedStringResource {
        switch self {
        case .reviewRequested: "Pull requests waiting for my review"
        case .myPullRequests: "My open pull requests"
        case .assignedIssues: "Issues assigned to me"
        }
    }
}

enum LiveFolderError: LocalizedError {
    case notSignedIn, unreadable

    var errorDescription: String? {
        switch self {
        case .notSignedIn: String(localized: "Sign in to GitHub to update this folder.")
        case .unreadable: String(localized: "This address isn't an RSS or Atom feed.")
        }
    }
}

enum LiveSourceReader {
    static func items(of source: LiveSource) async throws -> [LiveItem] {
        let items = switch source.kind {
        case .feed: try await FeedReader.items(at: source.value)
        case .github: try await GitHubAccount.shared.search(source.value)
        }
        return Array(items.filter { !source.dismissed.contains($0.id) }.prefix(LiveSource.maxItems))
    }
}
