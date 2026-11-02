import SwiftUI

/// The top of the sidebar, next to the window buttons: hiding the sidebar, the space's name, then
/// back, forward and reload for the page shown.
struct SidebarHeader: View {
    let state: BrowserState

    /// Room for the window buttons.
    static let windowButtonsWidth: CGFloat = 58

    var body: some View {
        // The space's name goes under the buttons when the sidebar is too narrow for it.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 2) {
                sidebarButton
                spaceName.padding(.leading, 4)
                Spacer(minLength: 8)
                pageButtons
            }
            .padding(.leading, Self.windowButtonsWidth)
            .frame(height: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 2) {
                    sidebarButton
                    Spacer()
                    pageButtons
                }
                .padding(.leading, Self.windowButtonsWidth)
                .frame(height: 30)
                spaceName
                    .padding(.leading, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var spaceName: some View {
        Text(state.selectedSpace.name)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
    }

    private var sidebarButton: some View {
        HeaderButton(symbol: "sidebar.left", help: "Hide Sidebar (⌘S)") {
            NSApp.sendAction(#selector(AppDelegate.showOrHideSidebar(_:)), to: nil, from: nil)
        }
    }

    @ViewBuilder private var pageButtons: some View {
        let tab = state.selectedTab
        HeaderButton(symbol: "arrow.left", help: "Back") { tab?.goBack() }
            .disabled(tab?.canGoBack != true)
        HeaderButton(symbol: "arrow.right", help: "Forward") { tab?.goForward() }
            .disabled(tab?.canGoForward != true)
        HeaderButton(symbol: "arrow.clockwise", help: "Reload (⌘R)") { tab?.browserView.reload() }
            .disabled(tab == nil)
        if let tab, state.isDeveloperModeOnSelectedTab {
            Menu {
                Button("Reload") { tab.browserView.reload() }
                Button("Reload Ignoring Cache") { tab.browserView.reloadIgnoringCache() }
                Divider()
                Button("Clear Cookies and Reload") { tab.clearCookiesAndReload() }
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 18)
            .help("More Ways to Reload")
        }
    }
}

struct HeaderButton: View {
    let symbol: String
    let help: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
