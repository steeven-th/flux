import Foundation

enum AppPaths {
    static let support: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "Flux", directoryHint: .isDirectory)

    static let database = support.appending(path: "Flux.sqlite")

    /// Chromium's root folder. Every profile lives directly inside it.
    static let chromiumRoot = support.appending(path: "Chromium", directoryHint: .isDirectory)

    static func profileFolder(named name: String) -> URL {
        chromiumRoot.appending(path: name, directoryHint: .isDirectory)
    }
}
