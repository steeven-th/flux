import SwiftUI

/// Downloads and media, in place of the sidebar.
struct LibraryView: View {
    @Bindable var state: BrowserState

    enum Section: Hashable {
        case media, downloads
    }

    @State private var section = Section.downloads
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    state.isLibraryShown = false
                } label: {
                    Image(systemName: "chevron.left").frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Back to Tabs")
                Picker("Library", selection: $section) {
                    Text("Media").tag(Section.media)
                    Text("Downloads").tag(Section.downloads)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            TextField(section == .media ? "Search Media" : "Search Downloads", text: $search)
                .textFieldStyle(.roundedBorder)
            switch section {
            case .downloads: DownloadsSection(state: state, search: search)
            case .media: MediaSection(library: state.mediaLibrary, search: search)
            }
        }
        .onAppear {
            state.downloadsOfSelectedSpace?.reload()
            state.mediaLibrary.refresh()
        }
    }
}

private struct DownloadsSection: View {
    let state: BrowserState
    let search: String

    var body: some View {
        let records = filtered
        if records.isEmpty {
            Text(search.isEmpty ? "No downloads in this space" : "No results")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(periods(of: records), id: \.title) { period in
                    SwiftUI.Section(period.title) {
                        ForEach(period.records) { record in
                            HStack(spacing: 10) {
                                FileThumbnail(url: record.fileURL, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.fileURL.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                    Text(record.details).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .fileActions(record.fileURL, onHide: { state.downloadsOfSelectedSpace?.remove(record) })
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    private var filtered: [DownloadRecord] {
        let all = state.downloadsOfSelectedSpace?.finished ?? []
        guard !search.isEmpty else { return all }
        return all.filter { $0.fileURL.lastPathComponent.localizedStandardContains(search) || $0.url.localizedStandardContains(search) }
    }

    /// Grouped by how long ago, in the words of the system: "today", "3 days ago", "1 week ago".
    private func periods(of records: [DownloadRecord]) -> [(title: String, records: [DownloadRecord])] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        var periods: [(title: String, records: [DownloadRecord])] = []
        for record in records {
            let day = calendar.startOfDay(for: record.finishedAt)
            let words = formatter.localizedString(for: day, relativeTo: today)
            let title = words.prefix(1).uppercased() + words.dropFirst()
            if periods.last?.title == title {
                periods[periods.count - 1].records.append(record)
            } else {
                periods.append((title, [record]))
            }
        }
        return periods
    }
}

private struct MediaSection: View {
    let library: MediaLibrary
    let search: String

    var body: some View {
        let items = filtered
        if items.isEmpty {
            Text(search.isEmpty ? "No screenshots or images in Downloads" : "No results")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        FileThumbnail(url: item.url, size: 110)
                            .frame(maxWidth: .infinity)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(0.06)))
                            .help(item.url.lastPathComponent)
                            .fileActions(
                                item.url,
                                onOpen: { QuickLookPreview.shared.show(items.map(\.url), at: index) },
                                onHide: { library.hide(item.url) }
                            )
                    }
                }
            }
        }
    }

    private var filtered: [MediaLibrary.Item] {
        guard !search.isEmpty else { return library.items }
        return library.items.filter { $0.url.lastPathComponent.localizedStandardContains(search) }
    }
}
