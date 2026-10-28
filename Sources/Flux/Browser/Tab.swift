import AppKit
import Observation

@MainActor
@Observable
final class Tab: NSObject, Identifiable {
    let id = UUID()
    let spaceID: UUID
    private(set) var url: String
    private(set) var title = ""

    @ObservationIgnored let browserView: FLXBrowserView

    init(url: String, spaceID: UUID, profile: FLXProfile) {
        self.url = url
        self.spaceID = spaceID
        browserView = FLXBrowserView(url: url, profile: profile)
        super.init()
        browserView.delegate = self
    }

    var displayTitle: String {
        title.isEmpty ? url : title
    }

    func load(_ url: String) {
        self.url = url
        browserView.loadURL(url)
    }
}

extension Tab: FLXBrowserViewDelegate {
    func browserView(_ browserView: FLXBrowserView, didChangeURL url: String) {
        self.url = url
    }

    func browserView(_ browserView: FLXBrowserView, didChangeTitle title: String) {
        self.title = title
    }
}
