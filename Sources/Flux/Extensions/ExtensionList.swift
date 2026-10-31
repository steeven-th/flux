import Foundation
import Observation

/// The extensions enabled in one profile, updated as soon as Chromium installs, removes, enables
/// or disables one.
@MainActor
@Observable
final class ExtensionList {
    private(set) var extensions: [InstalledExtension] = []
    /// Enabled or not.
    private(set) var installedIDs: Set<String> = []

    /// Called with an extension just installed, not with those found when the profile loads.
    @ObservationIgnored var onInstall: ((InstalledExtension) -> Void)?
    /// False until Chromium has given the profile's extensions.
    @ObservationIgnored private(set) var isLoaded = false
    @ObservationIgnored private let extensionsFolder: URL

    init(profile: FLXProfile, profileFolder: URL) {
        extensionsFolder = profileFolder.appending(path: "Extensions")
        profile.observePreference("extensions.settings") { [weak self] value in
            MainActor.assumeIsolated {
                guard let self else { return }
                let settings = value as? [String: Any] ?? [:]
                let previousIDs = self.installedIDs
                self.extensions = Self.enabledExtensions(in: settings, folder: self.extensionsFolder)
                self.installedIDs = Set(settings.filter { ($0.value as? [String: Any])?["location"] as? Int == 1 }.keys)
                if self.isLoaded {
                    self.extensions.filter { !previousIDs.contains($0.id) }.forEach { self.onInstall?($0) }
                }
                self.isLoaded = true
            }
        }
    }

    private static func enabledExtensions(in settings: [String: Any], folder: URL) -> [InstalledExtension] {
        settings.compactMap { id, value in
            // Location 1 is an extension the user installed. Chromium's own components use others.
            guard let setting = value as? [String: Any],
                  setting["location"] as? Int == 1,
                  (setting["disable_reasons"] as? [Any])?.isEmpty ?? true,
                  let path = setting["path"] as? String else { return nil }
            let extensionFolder = path.hasPrefix("/") ? URL(filePath: path) : folder.appending(path: path)
            return InstalledExtension(id: id, folder: extensionFolder)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
