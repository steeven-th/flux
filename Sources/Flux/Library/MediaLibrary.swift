import AppKit
import Observation
import UniformTypeIdentifiers

/// Screenshots, wherever macOS saves them, and the files of the Downloads folder, whichever app put
/// them there.
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
    /// Every file of the Downloads folder, the latest first.
    private(set) var downloadsFolderFiles: [Item] = []

    /// Files hidden from the library, which stay where they are.
    private static let hiddenKey = "hiddenMedia"
    @ObservationIgnored private var hidden = Set(UserDefaults.standard.stringArray(forKey: hiddenKey) ?? [])

    @ObservationIgnored private let screenshotQuery = NSMetadataQuery()
    @ObservationIgnored private var downloadsFolderItems: [Item] = []
    @ObservationIgnored private var folderWatch: DispatchSourceFileSystemObject?
    /// Partial files of downloads still running, in Chromium, Safari and Firefox.
    private static let partialExtensions: Set<String> = ["crdownload", "download", "part"]

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
        watchDownloadsFolder()
    }

    private static var downloadsFolder: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    /// Files saved there by other apps, such as a mail attachment, show without waiting.
    private func watchDownloadsFolder() {
        guard let folder = Self.downloadsFolder else { return }
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        folderWatch = source
    }

    /// Set in the Screenshot app's options, the Desktop otherwise.
    private static var screenshotFolder: URL {
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            return URL(filePath: (path as NSString).expandingTildeInPath, directoryHint: .isDirectory)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    func refresh() {
        guard let folder = Self.downloadsFolder else { return }
        let keys: [URLResourceKey] = [.contentTypeKey, .addedToDirectoryDateKey, .creationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        )) ?? []
        var files: [(item: Item, type: UTType?)] = []
        for url in urls where !Self.partialExtensions.contains(url.pathExtension.lowercased()) {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let date = values.addedToDirectoryDate ?? values.creationDate ?? .distantPast
            files.append((Item(url: url, date: date, isScreenshot: false), values.contentType))
        }
        downloadsFolderFiles = files.map(\.item).filter { !hidden.contains($0.url.path) }.sorted { $0.date > $1.date }
        downloadsFolderItems = files.filter { $0.type?.conforms(to: .image) == true || $0.type?.conforms(to: .movie) == true }.map(\.item)
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
        downloadsFolderFiles.removeAll { $0.url == url }
    }
}
