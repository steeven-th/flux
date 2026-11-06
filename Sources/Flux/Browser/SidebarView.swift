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

            SidebarDivider()

            VStack(alignment: .leading, spacing: 12) {
                SidebarOutline(state: state) { showCommandBar(.newTab) }
                PasswordExportCard(state: state)
                ImportedExtensionsCard(state: state)

                if !state.miniPlayerTabs.isEmpty {
                    MiniPlayerStack(state: state)
                        .opacity(recentFiles.isShown ? 0 : 1)
                        .allowsHitTesting(!recentFiles.isShown)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // The latest files rise over the bottom of the tabs, right above the space bar, and push
            // the player up. Between them, the player would grow under the pointer on its way to
            // the files.
            .overlay(alignment: .bottom) {
                if recentFiles.isShown {
                    VStack(spacing: 12) {
                        if !state.miniPlayerTabs.isEmpty {
                            MiniPlayerStack(state: state)
                        }
                        RecentFilesCard(state: state, presenter: recentFiles)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.18), value: recentFiles.isShown)

            SpaceBar(state: state, recentFiles: recentFiles)
        }
        .animation(.easeOut(duration: 0.2), value: state.miniPlayerTabs.isEmpty)
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
