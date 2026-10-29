import Quartz

/// Shows files in the Quick Look panel, as the space bar does in the Finder.
@MainActor
final class QuickLookPreview: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLookPreview()

    private var urls: [URL] = []

    func show(_ urls: [URL], at index: Int) {
        guard let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = index
        panel.makeKeyAndOrderFront(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { urls[index] as NSURL }
    }
}
