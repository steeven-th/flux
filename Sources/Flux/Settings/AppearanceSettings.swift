import SwiftUI

/// How the window is laid out, for every space. A space's own look is in Customize Space.
struct AppearanceSettings: View {
    @Bindable var state: BrowserState

    var body: some View {
        Form {
            Section {
                Picker("Sidebar", selection: $state.sidebarSide) {
                    ForEach(BrowserState.SidebarSide.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Tabs", selection: $state.sidebarDensity) {
                    ForEach(BrowserState.SidebarDensity.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Pinned tabs", selection: $state.pinnedTileSize) {
                    ForEach(BrowserState.PinnedTileSize.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Picker("Page", selection: $state.pageStyle) {
                    ForEach(BrowserState.PageStyle.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("A card leaves a margin around the page, with round corners. Edge to edge gives the page all the room.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("Each space's color, gradient, grain and light or dark look are in Customize Space, from the space's menu at the bottom of the sidebar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }
}
