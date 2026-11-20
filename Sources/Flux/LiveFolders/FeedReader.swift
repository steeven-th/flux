import Foundation

/// RSS 2.0 and Atom feeds. A site's address works too: its page names its feed.
enum FeedReader {
    struct Feed {
        let title: String?
        let items: [LiveItem]
        /// The feed's own address, which may differ from the one typed.
        let url: String
    }

    static func items(at address: String) async throws -> [LiveItem] {
        try await feed(at: address).items
    }

    static func feed(at address: String) async throws -> Feed {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespaces)) else { throw LiveFolderError.unreadable }
        let data = try await download(url)
        if let feed = parse(data, url: url) { return feed }
        guard let page = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              let linked = feedLink(in: page, base: url) else { throw LiveFolderError.unreadable }
        guard let feed = parse(try await download(linked), url: linked) else { throw LiveFolderError.unreadable }
        return feed
    }

    private static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/rss+xml, application/atom+xml, application/xml;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else { throw LiveFolderError.unreadable }
        return data
    }

    /// `<link rel="alternate" type="application/rss+xml" href="…">` in the page's head.
    private static func feedLink(in page: String, base: URL) -> URL? {
        let links = page.matches(of: /<link\b[^>]*>/.ignoresCase()).map { String(page[$0.range]) }
        for link in links where link.range(of: #"application/(rss|atom)\+xml"#, options: [.regularExpression, .caseInsensitive]) != nil {
            guard let href = link.firstMatch(of: /href\s*=\s*["']([^"']+)["']/.ignoresCase())?.1 else { continue }
            let decoded = String(href).replacingOccurrences(of: "&amp;", with: "&")
            if let url = URL(string: decoded, relativeTo: base)?.absoluteURL { return url }
        }
        return nil
    }

    private static func parse(_ data: Data, url: URL) -> Feed? {
        let parser = XMLParser(data: data)
        let delegate = Parser()
        parser.delegate = delegate
        guard parser.parse(), delegate.isFeed else { return nil }
        let items = delegate.items.compactMap { entry -> LiveItem? in
            guard let link = entry.link.flatMap({ URL(string: $0, relativeTo: url)?.absoluteString }) else { return nil }
            let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return LiveItem(id: entry.id ?? link, title: title.isEmpty ? link : title, url: link)
        }
        return Feed(title: delegate.title?.trimmingCharacters(in: .whitespacesAndNewlines), items: items, url: url.absoluteString)
    }

    private final class Parser: NSObject, XMLParserDelegate {
        struct Entry {
            var title = ""
            var link: String?
            var id: String?
        }

        private(set) var isFeed = false
        private(set) var title: String?
        private(set) var items: [Entry] = []
        private var entry: Entry?
        private var text = ""

        func parser(
            _ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
            attributes: [String: String] = [:]
        ) {
            text = ""
            switch name {
            case "rss", "feed", "rdf:RDF": isFeed = true
            case "item", "entry": entry = Entry()
            case "link" where entry != nil:
                // Atom links are attributes: the page is the alternate link, or the only one.
                if let href = attributes["href"], attributes["rel"] ?? "alternate" == "alternate" { entry?.link = href }
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, foundCDATA block: Data) {
            text += String(data: block, encoding: .utf8) ?? ""
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if var current = entry {
                switch name {
                case "title": current.title = value
                case "link" where !value.isEmpty: current.link = value
                case "guid", "id": if !value.isEmpty { current.id = value }
                case "item", "entry":
                    items.append(current)
                    entry = nil
                    return
                default: break
                }
                entry = current
            } else if name == "title", title == nil {
                title = value
            }
        }
    }
}
