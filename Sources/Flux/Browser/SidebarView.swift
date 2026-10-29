import SwiftUI

struct SidebarView: View {
    @Bindable var state: BrowserState
    @State private var address = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search or enter address", text: $address)
                .textFieldStyle(.roundedBorder)
                .onSubmit { state.open(address) }

            if !state.extensionsInSelectedSpace.isEmpty {
                ExtensionsBar(extensions: state.extensionsInSelectedSpace, profile: state.selectedProfile)
            }

            SidebarOutline(state: state)

            Button {
                state.newTab()
            } label: {
                Label("New Tab", systemImage: "plus")
            }
            .buttonStyle(.borderless)

            SpaceBar(state: state)
        }
        .padding(.horizontal, 12)
        .padding(.top, 36)
        .padding(.bottom, 12)
        .onChange(of: state.selectedTab?.url, initial: true) { _, url in
            address = url ?? ""
        }
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
