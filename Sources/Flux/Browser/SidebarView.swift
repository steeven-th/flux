import SwiftUI

struct SidebarView: View {
    @Bindable var state: BrowserState
    let showCommandBar: (CommandBarModel.Target) -> Void

    private var pinnedCount: Int {
        _ = state.sidebarRevision
        return state.pinnedTabs.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AddressButton(url: state.selectedTab?.url) {
                showCommandBar(.selectedTab)
            }

            if !state.extensionsInSelectedSpace.isEmpty {
                ExtensionsBar(extensions: state.extensionsInSelectedSpace, profile: state.selectedProfile) {
                    state.selectedTab?.browserView
                }
            }

            PinnedGrid(state: state)
                .frame(height: PinnedGrid.height(for: pinnedCount))

            SidebarOutline(state: state)

            Button {
                showCommandBar(.newTab)
            } label: {
                Label("New Tab", systemImage: "plus")
            }
            .buttonStyle(.borderless)

            SpaceBar(state: state)
        }
        .padding(.horizontal, 12)
        .padding(.top, 36)
        .padding(.bottom, 12)
    }
}

/// The selected tab's site. Clicking it opens the command bar to go elsewhere, like in Arc.
private struct AddressButton: View {
    let url: String?
    let action: () -> Void

    private var text: String {
        guard let url else { return "Search or Enter URL" }
        guard let host = URL(string: url)?.host() else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(.primary.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The selected space's tint behind the whole window, sidebar and page margins included.
struct SpaceBackground: View {
    let state: BrowserState

    var body: some View {
        state.selectedSpace.color.opacity(0.12)
            .ignoresSafeArea()
    }
}
