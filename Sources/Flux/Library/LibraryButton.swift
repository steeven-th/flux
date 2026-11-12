import SwiftUI

/// Whether the latest files show above the space bar. They show while the pointer is on the
/// library's button or on them, with a short delay so it can move from one to the other.
@MainActor
@Observable
final class RecentFilesPresenter {
    private(set) var isShown = false
    @ObservationIgnored private var isOverButton = false
    @ObservationIgnored private var isOverFiles = false

    func pointerOnButton(_ isOn: Bool) {
        isOverButton = isOn
        isOn ? showSoon() : hideSoon()
    }

    func pointerOnFiles(_ isOn: Bool) {
        isOverFiles = isOn
        if !isOn { hideSoon() }
    }

    func hide() {
        isShown = false
    }

    private func showSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            MainActor.assumeIsolated { if self?.isOverButton == true { self?.isShown = true } }
        }
    }

    private func hideSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isOverButton, !self.isOverFiles else { return }
                self.isShown = false
            }
        }
    }
}

/// The library's button at the bottom of the sidebar. Hovering shows the latest files, clicking
/// opens the library. A ring shows the progress of running downloads.
struct LibraryButton: View {
    @Bindable var state: BrowserState
    let recentFiles: RecentFilesPresenter

    var body: some View {
        Button {
            recentFiles.hide()
            state.isLibraryShown = true
        } label: {
            Image(systemName: "tray.full")
                .frame(width: 22, height: 22)
                .overlay {
                    if let progress = state.downloadsOfSelectedSpace?.progress {
                        Circle()
                            .trim(from: 0, to: max(progress, 0.05))
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 24, height: 24)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Library")
        .onHover { recentFiles.pointerOnButton($0) }
    }
}

/// A card rising from the bottom of the sidebar, in the space's color, rather than a popover: it
/// belongs to the sidebar.
struct RecentFilesCard: View {
    let state: BrowserState
    let presenter: RecentFilesPresenter

    var body: some View {
        RecentFiles(state: state)
            .background {
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                ZStack {
                    shape.fill(Color(nsColor: .windowBackgroundColor))
                    shape.fill(state.selectedSpace.color.opacity(0.22))
                }
                .overlay(shape.strokeBorder(.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.12), radius: 12, y: -2)
            }
            .onHover { presenter.pointerOnFiles($0) }
    }
}

/// The latest downloads and screenshots, the most recent at the bottom next to the button, then
/// the downloads running.
private struct RecentFiles: View {
    let state: BrowserState

    private struct Recent: Identifiable {
        let url: URL
        let date: Date
        let hide: () -> Void
        var id: URL { url }
    }

    var body: some View {
        let running = state.downloadsOfSelectedSpace?.inProgress ?? []
        let recent = recent
        VStack(alignment: .leading, spacing: 2) {
            if recent.isEmpty && running.isEmpty {
                Text("No downloads or screenshots yet")
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            ForEach(recent.reversed()) { item in
                RecentRow(url: item.url, onHide: item.hide) {
                    Text(item.date, format: .relative(presentation: .named)) + Text(Self.size(of: item.url))
                }
                .fileActions(item.url, onHide: item.hide)
            }
            ForEach(running, id: \.identifier) { download in
                RunningRow(download: download) { state.downloadsOfSelectedSpace?.cancel(download) }
            }
        }
        .padding(6)
    }

    private var recent: [Recent] {
        let list = state.downloadsOfSelectedSpace
        let media = state.mediaLibrary
        let downloads = (list?.finished ?? []).map { record in
            Recent(url: record.fileURL, date: record.finishedAt) { list?.remove(record) }
        }
        let screenshots = media.items.filter(\.isScreenshot).prefix(5).map { item in
            Recent(url: item.url, date: item.date) { media.hide(item.url) }
        }
        let others = state.otherDownloads.prefix(5).map { item in
            Recent(url: item.url, date: item.date) { media.hide(item.url) }
        }
        var seen = Set<URL>()
        return Array((downloads + screenshots + others).sorted { $0.date > $1.date }
            .filter { seen.insert($0.url).inserted }.prefix(5))
    }

    private static func size(of url: URL) -> String {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return "" }
        return " · " + ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

private struct RecentRow<Details: View>: View {
    let url: URL
    let onHide: () -> Void
    @ViewBuilder let details: () -> Details

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            FileThumbnail(url: url, size: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary.opacity(0.08)))
            VStack(alignment: .leading, spacing: 3) {
                Text(url.lastPathComponent)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                details()
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isHovered {
                Button { FileRemoval.confirm(url, onHide: onHide) } label: {
                    Image(systemName: "trash")
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Remove")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(isHovered ? 0.08 : 0)))
        .onHover { isHovered = $0 }
    }
}

private struct RunningRow: View {
    let download: FLXDownload
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 18))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.06)))
            VStack(alignment: .leading, spacing: 4) {
                Text(name).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                if download.totalBytes > 0 {
                    ProgressView(value: Double(download.receivedBytes), total: Double(download.totalBytes))
                        .controlSize(.small)
                } else {
                    ProgressView().progressViewStyle(.linear).controlSize(.small)
                }
                Text(progress).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Cancel Download")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var name: String {
        let name = URL(filePath: download.path).lastPathComponent
        return name.isEmpty ? download.url : name
    }

    /// "45 % · 45 MB of 100 MB"
    private var progress: String {
        let received = ByteCountFormatter.string(fromByteCount: download.receivedBytes, countStyle: .file)
        guard download.totalBytes > 0 else { return received }
        let total = ByteCountFormatter.string(fromByteCount: download.totalBytes, countStyle: .file)
        let percent = (Double(download.receivedBytes) / Double(download.totalBytes)).formatted(.percent.precision(.fractionLength(0)))
        return String(localized: "\(percent) · \(received) of \(total)")
    }
}
