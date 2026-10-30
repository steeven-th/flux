import SwiftUI

struct SidebarView: View {
    @Bindable var state: BrowserState
    let showCommandBar: (CommandBarModel.Target) -> Void
    @State private var width: CGFloat = 0
    @State private var recentFiles = RecentFilesPresenter()
    @State private var isHovered = false

    private var pinnedCount: Int {
        _ = state.sidebarRevision
        return state.pinnedTabs.count
    }

    var body: some View {
        VStack(spacing: 6) {
            SidebarHeader(state: state)
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
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 12)
        .onHover { isHovered = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.width - 24 } action: { width = $0 }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            AddressBar(state: state, isSidebarHovered: isHovered) {
                showCommandBar(.selectedTab)
            }

            PinnedGrid(state: state, width: width)
                .frame(height: PinnedGrid.height(for: pinnedCount, width: width))

            VStack(alignment: .leading, spacing: 12) {
                SidebarOutline(state: state)
                PasswordExportCard(state: state)
                ImportedExtensionsCard(state: state)

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

/// The selected space's tint behind the whole window, sidebar and page margins included.
struct SpaceBackground: View {
    static let tintOpacity = 0.12

    let state: BrowserState

    var body: some View {
        state.selectedSpace.color.opacity(Self.tintOpacity)
            .ignoresSafeArea()
    }
}
