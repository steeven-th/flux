import Foundation

/// Keeps the engine's content blocking rules up to date: downloads EasyList and EasyPrivacy every
/// few days, turns them into Chromium's rules with the engine's converter, and hands them over.
@MainActor
final class ContentBlocker {
    static let shared = ContentBlocker()

    /// EasyList's regional lists cover the ads of sites in a language, which EasyList leaves to
    /// them.
    private static let regionalLists = [
        "fr": "https://easylist-downloads.adblockplus.org/liste_fr.txt",
        "de": "https://easylist.to/easylistgermany/easylistgermany.txt",
        "it": "https://easylist-downloads.adblockplus.org/easylistitaly.txt",
        "es": "https://easylist-downloads.adblockplus.org/easylistspanish.txt",
        "nl": "https://easylist-downloads.adblockplus.org/easylistdutch.txt",
        "pt": "https://easylist-downloads.adblockplus.org/easylistportuguese.txt",
    ]

    /// EasyList and EasyPrivacy, and the regional lists of the Mac's languages.
    private static var lists: [URL] {
        let languages = Locale.preferredLanguages.compactMap { Locale.Language(identifier: $0).languageCode?.identifier }
        var seen = Set<String>()
        let regional = languages.filter { seen.insert($0).inserted }.compactMap { regionalLists[$0] }
        return (["https://easylist.to/easylist/easylist.txt", "https://easylist.to/easylist/easyprivacy.txt"] + regional)
            .compactMap(URL.init(string:))
    }
    /// The lists change a few times a day, so a few days is close enough.
    private static let refreshInterval: TimeInterval = 4 * 24 * 3600

    private let folder = AppPaths.support.appending(path: "Content Blocking", directoryHint: .isDirectory)
    private var rulesURL: URL { folder.appending(path: "rules.dat") }
    private var versionURL: URL { folder.appending(path: "version.txt") }
    private var sourcesURL: URL { folder.appending(path: "sources.txt") }
    private var sources: String { Self.lists.map(\.absoluteString).joined(separator: "\n") }
    private var isUpdating = false
    private var timer: Timer?
    private var hiding: ElementHiding?

    /// Chromium keeps the rules it indexed last, so the version on disk only needs indexing once.
    func start() {
        guard timer == nil else { return }
        if FileManager.default.fileExists(atPath: rulesURL.path),
           let version = try? String(contentsOf: versionURL, encoding: .utf8) {
            FLXEngine.useContentBlockingRules(at: rulesURL, version: version)
        }
        FLXBrowserView.contentHidingScriptProvider = { host, message in
            MainActor.assumeIsolated { ContentBlocker.shared.hiding?.script(forHost: host, message: message) }
        }
        loadElementHiding()
        updateIfNeeded()
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            MainActor.assumeIsolated { ContentBlocker.shared.updateIfNeeded() }
        }
    }

    private func updateIfNeeded() {
        let modified = try? rulesURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        // A language added to the Mac brings its list in at once.
        let listsChanged = (try? String(contentsOf: sourcesURL, encoding: .utf8)) != sources
        guard !isUpdating, listsChanged || modified.map({ -$0.timeIntervalSinceNow > Self.refreshInterval }) ?? true else { return }
        isUpdating = true
        Task {
            do {
                try await update()
            } catch {
                NSLog("Content blocking lists not updated: %@", String(describing: error))
            }
            isUpdating = false
        }
    }

    private func update() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var inputs: [URL] = []
        for (index, list) in Self.lists.enumerated() {
            let (data, response) = try await URLSession.shared.data(from: list)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let file = folder.appending(path: "list-\(index).txt")
            try data.write(to: file)
            inputs.append(file)
        }
        let converted = folder.appending(path: "rules.new")
        try await convert(inputs, to: converted)
        if FileManager.default.fileExists(atPath: rulesURL.path) {
            _ = try FileManager.default.replaceItemAt(rulesURL, withItemAt: converted)
        } else {
            try FileManager.default.moveItem(at: converted, to: rulesURL)
        }
        let version = ISO8601DateFormatter().string(from: Date())
        try version.write(to: versionURL, atomically: true, encoding: .utf8)
        try sources.write(to: sourcesURL, atomically: true, encoding: .utf8)
        FLXEngine.useContentBlockingRules(at: rulesURL, version: version)
        loadElementHiding()
    }

    /// From the lists on disk, off the main thread: they hold a few hundred thousand lines.
    private func loadElementHiding() {
        let files = Self.lists.indices.map { folder.appending(path: "list-\($0).txt") }
        Task.detached(priority: .utility) {
            let lists = files.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            guard !lists.isEmpty else { return }
            let hiding = ElementHiding(lists: lists)
            await MainActor.run { ContentBlocker.shared.hiding = hiding }
        }
    }

    /// Rules with options Chromium doesn't support, and element hiding rules, are left out.
    private func convert(_ inputs: [URL], to output: URL) async throws {
        let process = Process()
        process.executableURL = FLXEngine.rulesetConverterURL
        process.arguments = [
            "--input_format=filter-list", "--output_format=unindexed-ruleset",
            "--input_files=" + inputs.map(\.path).joined(separator: ","), "--output_file=" + output.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: CocoaError(.executableLoad))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
