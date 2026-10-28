import Foundation

enum AppPaths {
    static let support: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "Flux", directoryHint: .isDirectory)

    /// Chromium's root folder. Every profile lives directly inside it.
    static let chromiumRoot = support.appending(path: "Chromium", directoryHint: .isDirectory)

    static func profileFolder(for spaceID: UUID) -> URL {
        chromiumRoot.appending(path: "Space \(spaceID.uuidString)", directoryHint: .isDirectory)
    }
}
