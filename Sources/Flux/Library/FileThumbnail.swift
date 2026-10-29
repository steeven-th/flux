import QuickLookThumbnailing
import SwiftUI

/// A file's Quick Look thumbnail, or its icon until the thumbnail is ready.
struct FileThumbnail: View {
    let url: URL
    let size: CGFloat

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .task(id: url) { image = await ThumbnailCache.shared.thumbnail(for: url, size: size) }
    }
}

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private var images: [String: NSImage] = [:]

    func thumbnail(for url: URL, size: CGFloat) async -> NSImage? {
        let key = "\(url.path)@\(Int(size))"
        if let image = images[key] { return image }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: size, height: size), scale: scale, representationTypes: .thumbnail
        )
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        images[key] = representation.nsImage
        return representation.nsImage
    }
}
