import SwiftUI

struct SidebarView: View {
    @Bindable var state: BrowserState
    @State private var address = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Space", selection: $state.selectedSpaceID) {
                ForEach(state.spaces) { space in
                    Text(space.name).tag(space.id)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField("Search or enter address", text: $address)
                .textFieldStyle(.roundedBorder)
                .onSubmit { state.open(address) }

            if !state.extensionsInSelectedSpace.isEmpty {
                ExtensionsBar(extensions: state.extensionsInSelectedSpace, profile: state.selectedProfile)
            }

            List(selection: selection) {
                ForEach(state.tabsInSelectedSpace) { tab in
                    Text(tab.displayTitle)
                        .lineLimit(1)
                        .tag(tab.id)
                        .contextMenu {
                            Button("Close Tab") { state.close(tab) }
                        }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Button {
                state.newTab()
            } label: {
                Label("New Tab", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.top, 36)
        .padding(.bottom, 12)
        .onChange(of: state.selectedTab?.url, initial: true) { _, url in
            address = url ?? ""
        }
    }

    private var selection: Binding<UUID?> {
        Binding(
            get: { state.selectedTab?.id },
            set: { id in
                if let tab = state.tabs.first(where: { $0.id == id }) {
                    state.select(tab)
                }
            }
        )
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
