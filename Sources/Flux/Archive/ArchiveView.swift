import SwiftUI

/// The selected space's archived tabs, by day. Clicking one opens it again in Today.
struct ArchiveView: View {
    let state: BrowserState

    @State private var search = ""
    @State private var asksToClear = false

    var body: some View {
        let tabs = filteredTabs
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search Archive", text: $search)
                .textFieldStyle(.roundedBorder)
            if tabs.isEmpty {
                Text(search.isEmpty ? "No archived tabs" : "No results")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(days(of: tabs), id: \.day) { group in
                        Section(header: Text(title(for: group.day))) {
                            ForEach(group.tabs) { tab in
                                ArchivedTabRow(tab: tab, favicon: state.favicon(for: tab.url))
                                    .contentShape(Rectangle())
                                    .onTapGesture { state.restore(tab) }
                                    .contextMenu {
                                        Button("Remove from Archive") { state.deleteFromArchive(tab) }
                                    }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            HStack {
                Text("Kept for 30 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear Archive…") { asksToClear = true }
                    .disabled(state.archivedTabsInSelectedSpace.isEmpty)
            }
        }
        .padding(12)
        .frame(width: 340, height: 440)
        .alert("Clear the archive of this space?", isPresented: $asksToClear) {
            Button("Clear", role: .destructive) { state.clearArchiveOfSelectedSpace() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Archived tabs can't be opened from here anymore. Their pages stay in the history.")
        }
    }

    private var filteredTabs: [ArchivedTab] {
        let tabs = state.archivedTabsInSelectedSpace
        let text = search.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return tabs }
        return tabs.filter { $0.title.localizedStandardContains(text) || $0.url.localizedStandardContains(text) }
    }

    private func days(of tabs: [ArchivedTab]) -> [(day: Date, tabs: [ArchivedTab])] {
        let calendar = Calendar.current
        var groups: [(day: Date, tabs: [ArchivedTab])] = []
        for tab in tabs {
            let day = calendar.startOfDay(for: tab.archivedAt)
            if groups.last?.day == day {
                groups[groups.count - 1].tabs.append(tab)
            } else {
                groups.append((day, [tab]))
            }
        }
        return groups
    }

    private func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return String(localized: "Today") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday") }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

private struct ArchivedTabRow: View {
    let tab: ArchivedTab
    let favicon: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let favicon {
                    Image(nsImage: favicon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "globe").foregroundStyle(.secondary)
                }
            }
            .frame(width: 16, height: 16)
            Text(tab.title.isEmpty ? tab.url : tab.title)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(tab.archivedAt.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
