import AppKit

/// Favicons by host, kept on disk in the profile folder so restored tabs show their icon before
/// their page is loaded.
@MainActor
final class FaviconCache {
    private let folder: URL
    private var images: [String: NSImage] = [:]

    init(profileFolder: URL) {
        folder = profileFolder.appending(path: "Flux Favicons", directoryHint: .isDirectory)
    }

    func image(for url: String) -> NSImage? {
        guard let host = Self.host(of: url) else { return nil }
        if let image = images[host] {
            return image
        }
        let image = NSImage(contentsOf: file(for: host))
        images[host] = image
        return image
    }

    func store(_ image: NSImage, for url: String) {
        guard let host = Self.host(of: url) else { return }
        images[host] = image
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? png.write(to: file(for: host))
    }

    private func file(for host: String) -> URL {
        folder.appending(path: "\(host).png")
    }

    private static func host(of url: String) -> String? {
        guard let host = URL(string: url)?.host(), !host.contains("/") else { return nil }
        return host
    }
}
