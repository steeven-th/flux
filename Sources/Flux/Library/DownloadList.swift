import Foundation
import Observation

/// A profile's downloads: those in progress, and the finished ones whose file is still there.
@MainActor
@Observable
final class DownloadList {
    private(set) var finished: [DownloadRecord] = []
    private(set) var inProgress: [FLXDownload] = []

    @ObservationIgnored private let database: ProfileDatabase

    init(profile: FLXProfile, database: ProfileDatabase) {
        self.database = database
        reload()
        // Chrome's own download bubble would show over the page. The library replaces it.
        profile.setPreference("download_bubble.partial_view_enabled", boolValue: false)
        profile.downloadHandler = { [weak self] download in
            MainActor.assumeIsolated { self?.update(download) }
        }
    }

    /// Between 0 and 1 for downloads of a known size, nil when none is running.
    var progress: Double? {
        let sized = inProgress.filter { $0.totalBytes > 0 }
        guard !inProgress.isEmpty else { return nil }
        guard !sized.isEmpty else { return 0 }
        let received = sized.reduce(0) { $0 + Double($1.receivedBytes) }
        let total = sized.reduce(0) { $0 + Double($1.totalBytes) }
        return received / total
    }

    func reload() {
        let records = (try? database.downloads()) ?? []
        finished = records.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func remove(_ record: DownloadRecord) {
        try? database.deleteDownload(id: record.id)
        finished.removeAll { $0.id == record.id }
    }

    /// Also takes the download off the list at once, should Chromium not report it again.
    func cancel(_ download: FLXDownload) {
        download.cancel()
        inProgress.removeAll { $0.identifier == download.identifier }
    }

    private func update(_ download: FLXDownload) {
        inProgress.removeAll { $0.identifier == download.identifier }
        switch download.state {
        case .inProgress:
            inProgress.append(download)
        case .complete:
            let record = DownloadRecord(
                id: UUID(), path: download.path, url: download.url, mimeType: download.mimeType,
                size: max(download.totalBytes, download.receivedBytes), finishedAt: Date()
            )
            try? database.save(record)
            finished.insert(record, at: 0)
        default:
            break
        }
    }
}
