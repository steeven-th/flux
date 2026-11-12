import SwiftUI
import UniformTypeIdentifiers

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

    /// A download of the space, or a file another app put in the Downloads folder.
    private struct Entry: Identifiable {
        let url: URL
        let date: Date
        let details: String
        let hide: () -> Void
        var id: URL { url }
    }

    var body: some View {
        let entries = filtered
        if entries.isEmpty {
            Text(search.isEmpty ? "No downloads in this space" : "No results")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(periods(of: entries), id: \.title) { period in
                    SwiftUI.Section(period.title) {
                        ForEach(period.entries) { entry in
                            HStack(spacing: 10) {
                                FileThumbnail(url: entry.url, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                    Text(entry.details).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .fileActions(entry.url, onHide: entry.hide)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    private var filtered: [Entry] {
        let list = state.downloadsOfSelectedSpace
        let downloads = (list?.finished ?? []).map { record in
            Entry(url: record.fileURL, date: record.finishedAt, details: record.details) { list?.remove(record) }
        }
        let media = state.mediaLibrary
        let others = state.otherDownloads.map { item in
            Entry(url: item.url, date: item.date, details: Self.kind(of: item.url)) { media.hide(item.url) }
        }
        let all = (downloads + others).sorted { $0.date > $1.date }
        guard !search.isEmpty else { return all }
        return all.filter { $0.url.lastPathComponent.localizedStandardContains(search) || $0.details.localizedStandardContains(search) }
    }

    private static func kind(of url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?.localizedDescription ?? ""
    }

    /// Grouped by how long ago, in the words of the system: "today", "3 days ago", "1 week ago".
    private func periods(of entries: [Entry]) -> [(title: String, entries: [Entry])] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        var periods: [(title: String, entries: [Entry])] = []
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            let words = formatter.localizedString(for: day, relativeTo: today)
            let title = words.prefix(1).uppercased() + words.dropFirst()
            if periods.last?.title == title {
                periods[periods.count - 1].entries.append(entry)
            } else {
                periods.append((title, [entry]))
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
