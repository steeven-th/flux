import SwiftUI

struct SidebarView: View {
    @Bindable var state: BrowserState
    let showCommandBar: (CommandBarModel.Target) -> Void
    @State private var width: CGFloat = 0
    @State private var recentFiles = RecentFilesPresenter()

    private var pinnedCount: Int {
        _ = state.sidebarRevision
        return state.pinnedTabs.count
    }

    var body: some View {
        ZStack {
            if state.isLibraryShown {
                LibraryView(state: state)
                    .transition(.move(edge: .trailing))
            } else {
                content
                    .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: state.isLibraryShown)
        .padding(.horizontal, 12)
        .padding(.top, 36)
        .padding(.bottom, 12)
        .onGeometryChange(for: CGFloat.self) { $0.size.width - 24 } action: { width = $0 }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            AddressButton(url: state.selectedTab?.url) {
                showCommandBar(.selectedTab)
            }

            if !state.extensionsInSelectedSpace.isEmpty {
                ExtensionsBar(extensions: state.extensionsInSelectedSpace, profile: state.selectedProfile) {
                    state.selectedTab?.browserView
                }
            }

            PinnedGrid(state: state, width: width)
                .frame(height: PinnedGrid.height(for: pinnedCount, width: width))

            VStack(alignment: .leading, spacing: 12) {
                SidebarOutline(state: state)

                HStack {
                    Button {
                        showCommandBar(.newTab)
                    } label: {
                        Label("New Tab", systemImage: "plus")
                    }
                    Spacer()
                    Button {
                        state.isArchiveShown.toggle()
                    } label: {
                        Image(systemName: "archivebox")
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .help("Archive")
                    .popover(isPresented: $state.isArchiveShown, arrowEdge: .top) {
                        ArchiveView(state: state)
                    }
                }
                .buttonStyle(.borderless)
            }
            // The latest files rise over the bottom of the tabs, above the space bar.
            .overlay(alignment: .bottom) {
                if recentFiles.isShown {
                    RecentFilesCard(state: state, presenter: recentFiles)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.18), value: recentFiles.isShown)

            SpaceBar(state: state, recentFiles: recentFiles)
        }
    }
}

/// The selected tab's site. Clicking it opens the command bar to go elsewhere, like in Arc.
private struct AddressButton: View {
    let url: String?
    let action: () -> Void

    private var text: String {
        guard let url else { return String(localized: "Search or Enter URL") }
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
    static let tintOpacity = 0.12

    let state: BrowserState

    var body: some View {
        state.selectedSpace.color.opacity(Self.tintOpacity)
            .ignoresSafeArea()
    }
}
