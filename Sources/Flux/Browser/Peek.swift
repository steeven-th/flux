import AppKit
import Observation

/// A page opened from a link, shown over the selected tab until it is closed or kept as a tab.
@MainActor
@Observable
final class Peek: NSObject {
    let page: FLXBrowserView
    let spaceID: UUID
    private(set) var url: String
    private(set) var title = ""
    private(set) var favicon: NSImage?

    @ObservationIgnored var onOpenPage: ((FLXBrowserView, FLXOpenDisposition) -> Void)?
    /// Called when the page closes itself.
    @ObservationIgnored var onClose: (() -> Void)?

    init(page: FLXBrowserView, spaceID: UUID, favicon: NSImage?) {
        self.page = page
        self.spaceID = spaceID
        self.favicon = favicon
        url = page.currentURL
        super.init()
        page.delegate = self
    }
}

extension Peek: FLXBrowserViewDelegate {
    func browserView(_ browserView: FLXBrowserView, didChangeURL url: String) {
        self.url = url
    }

    func browserView(_ browserView: FLXBrowserView, didChangeTitle title: String) {
        self.title = title
    }

    func browserView(_ browserView: FLXBrowserView, didChangeFavicon favicon: NSImage) {
        self.favicon = favicon
    }

    func browserView(_ browserView: FLXBrowserView, didOpenPage page: FLXBrowserView, disposition: FLXOpenDisposition) {
        onOpenPage?(page, disposition)
    }

    func browserViewDidClose(_ browserView: FLXBrowserView) {
        onClose?()
    }

    func browserViewDidOpenOnlyDownload(_ browserView: FLXBrowserView) {
        onClose?()
    }
}
