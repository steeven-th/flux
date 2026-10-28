import Foundation
import Observation

/// The extensions enabled in one profile, kept up to date while Chromium installs, removes or
/// disables them.
@MainActor
@Observable
final class ExtensionList {
    private(set) var extensions: [InstalledExtension] = []

    @ObservationIgnored private let profileFolder: URL
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var pendingReload: DispatchWorkItem?

    init(profileFolder: URL) {
        self.profileFolder = profileFolder
        reload()
        watchProfileFolder()
    }

    func reload() {
        extensions = Self.read(profileFolder: profileFolder)
    }

    /// Chromium saves its preferences by writing a new file and renaming it, which changes the
    /// profile folder itself.
    private func watchProfileFolder() {
        try? FileManager.default.createDirectory(at: profileFolder, withIntermediateDirectories: true)
        let descriptor = open(profileFolder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private static func read(profileFolder: URL) -> [InstalledExtension] {
        guard let data = try? Data(contentsOf: profileFolder.appending(path: "Secure Preferences")),
              let preferences = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let settings = (preferences["extensions"] as? [String: Any])?["settings"] as? [String: [String: Any]] else {
            return []
        }
        let extensionsFolder = profileFolder.appending(path: "Extensions")
        return settings.compactMap { id, setting in
            // Location 1 is an extension the user installed. Chromium's own components use others.
            guard setting["location"] as? Int == 1,
                  (setting["disable_reasons"] as? [Any])?.isEmpty ?? true,
                  let path = setting["path"] as? String else { return nil }
            let folder = path.hasPrefix("/") ? URL(filePath: path) : extensionsFolder.appending(path: path)
            return InstalledExtension(id: id, folder: folder)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
