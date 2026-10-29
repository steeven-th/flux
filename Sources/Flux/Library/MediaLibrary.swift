import AppKit
import Observation
import UniformTypeIdentifiers

/// Screenshots, wherever macOS saves them, and the images and videos of the Downloads folder.
@MainActor
@Observable
final class MediaLibrary {
    struct Item: Identifiable, Hashable {
        let url: URL
        let date: Date
        let isScreenshot: Bool

        var id: URL { url }
    }

    private(set) var items: [Item] = []

    /// Files hidden from the library, which stay where they are.
    private static let hiddenKey = "hiddenMedia"
    @ObservationIgnored private var hidden = Set(UserDefaults.standard.stringArray(forKey: hiddenKey) ?? [])

    @ObservationIgnored private let screenshotQuery = NSMetadataQuery()
    @ObservationIgnored private var downloadsFolderItems: [Item] = []

    init() {
        // Spotlight knows screenshots by this attribute. Only those of the folder macOS saves them
        // to: elsewhere, such as iCloud Drive, they are files the user put away.
        screenshotQuery.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        screenshotQuery.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSCreationDateKey, ascending: false)]
        screenshotQuery.searchScopes = [Self.screenshotFolder]
        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            center.addObserver(forName: name, object: screenshotQuery, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.merge() }
            }
        }
        screenshotQuery.start()
        refresh()
    }

    /// Set in the Screenshot app's options, the Desktop otherwise.
    private static var screenshotFolder: URL {
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            return URL(filePath: (path as NSString).expandingTildeInPath, directoryHint: .isDirectory)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    /// The Downloads folder has no live query, so it is read again when the library shows.
    func refresh() {
        guard let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        let keys: [URLResourceKey] = [.contentTypeKey, .creationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        )) ?? []
        downloadsFolderItems = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), let type = values.contentType,
                  type.conforms(to: .image) || type.conforms(to: .movie) else { return nil }
            return Item(url: url, date: values.creationDate ?? .distantPast, isScreenshot: false)
        }
        merge()
    }

    private func merge() {
        screenshotQuery.disableUpdates()
        let screenshots = screenshotQuery.results.compactMap { result -> Item? in
            guard let item = result as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
            let date = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date ?? .distantPast
            return Item(url: URL(filePath: path), date: date, isScreenshot: true)
        }
        screenshotQuery.enableUpdates()
        let screenshotURLs = Set(screenshots.map(\.url))
        items = (screenshots + downloadsFolderItems.filter { !screenshotURLs.contains($0.url) })
            .filter { !hidden.contains($0.url.path) && FileManager.default.fileExists(atPath: $0.url.path) }
            .sorted { $0.date > $1.date }
    }

    func hide(_ url: URL) {
        hidden.insert(url.path)
        UserDefaults.standard.set(Array(hidden), forKey: Self.hiddenKey)
        items.removeAll { $0.url == url }
    }
}
