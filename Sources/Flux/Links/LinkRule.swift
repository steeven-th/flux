import AppKit
import GRDB

/// Where a link from another app opens, when it matches. Rules are tried in order and the first
/// that matches wins, like Arc's.
struct LinkRule: Codable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "linkRule"

    var id: UUID
    var position: Int
    /// Matched anywhere in the link, ignoring case.
    var urlContains: String?
    var sourceAppID: String?
    /// Kept to show the rule when the app is gone.
    var sourceAppName: String?
    /// Nil for the space shown when the link comes.
    var spaceID: UUID?
    var opensLittleWindow: Bool

    var sourceApp: SourceApp? {
        get { sourceAppID.map { SourceApp(bundleID: $0, name: sourceAppName ?? $0) } }
        set {
            sourceAppID = newValue?.bundleID
            sourceAppName = newValue?.name
        }
    }

    /// A rule without a condition would catch every link.
    var hasCondition: Bool {
        !(urlContains ?? "").isEmpty || sourceApp != nil
    }

    func matches(_ url: URL, from app: SourceApp?) -> Bool {
        guard hasCondition else { return false }
        if let text = urlContains, !text.isEmpty, !url.absoluteString.localizedCaseInsensitiveContains(text) {
            return false
        }
        if let sourceApp, sourceApp.bundleID != app?.bundleID {
            return false
        }
        return true
    }
}

/// The app a link comes from.
struct SourceApp: Codable, Hashable {
    let bundleID: String
    let name: String

    /// The app of the process that sent the Apple event being handled. Apps often open links from
    /// a helper inside their bundle, so the outermost app of its path is the one.
    static func sendingCurrentEvent() -> SourceApp? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value,
              pid > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let components = URL(filePath: String(cString: buffer)).pathComponents
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return SourceApp(bundleURL: URL(filePath: NSString.path(withComponents: Array(components[...index]))))
    }

    init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    init?(bundleURL: URL) {
        guard let bundleID = Bundle(url: bundleURL)?.bundleIdentifier else { return nil }
        self.init(bundleID: bundleID, name: FileManager.default.displayName(atPath: bundleURL.path).replacing(/\.app$/, with: ""))
    }

    var icon: NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}
