import SwiftUI

/// The top of the sidebar, next to the window buttons: hiding the sidebar, then back, forward and
/// reload for the page shown.
struct SidebarHeader: View {
    let state: BrowserState

    /// Room for the window buttons.
    static let windowButtonsWidth: CGFloat = 58

    var body: some View {
        let tab = state.selectedTab
        HStack(spacing: 2) {
            HeaderButton(symbol: "sidebar.left", help: "Hide Sidebar (⌘S)") {
                NSApp.sendAction(#selector(AppDelegate.showOrHideSidebar(_:)), to: nil, from: nil)
            }
            Spacer()
            HeaderButton(symbol: "arrow.left", help: "Back") { tab?.browserView.goBack() }
                .disabled(tab?.canGoBack != true)
            HeaderButton(symbol: "arrow.right", help: "Forward") { tab?.browserView.goForward() }
                .disabled(tab?.canGoForward != true)
            HeaderButton(symbol: "arrow.clockwise", help: "Reload (⌘R)") { tab?.browserView.reload() }
                .disabled(tab == nil)
        }
        .padding(.leading, Self.windowButtonsWidth)
        .frame(height: 30)
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
