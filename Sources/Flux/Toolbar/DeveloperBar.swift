import SwiftUI

/// The bar over a page whose site is in developer mode: its full address, and tools at hand.
struct DeveloperBar: View {
    let state: BrowserState

    static let height: CGFloat = 36

    var body: some View {
        VStack(spacing: 0) {
            if let tab = state.selectedTab {
                HStack(spacing: 2) {
                    Image(systemName: URL(string: tab.url)?.scheme == "https" ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 11))
                        .padding(.trailing, 4)
                    Text(tab.url)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 12)
                    CopyLinkButton(url: tab.url)
                    BarDivider()
                    ToolButton(symbol: "camera", help: "Capture an Area") { PageCapture.captureArea(of: tab, state: state) }
                    ToolButton(symbol: "text.viewfinder", help: "Capture the Whole Page") { PageCapture.captureWholePage(of: tab, state: state) }
                    let tools = state.devToolsInBar
                    if !tools.isEmpty {
                        BarDivider()
                        ForEach(tools) { tool in
                            Button { tab.show(tool) } label: {
                                Image(systemName: tool.symbol)
                                    .frame(width: 26, height: 26)
                                    .contentShape(Rectangle())
                            }
                            .help(tool.name)
                        }
                    }
                    if !state.pinnedExtensionsInSelectedSpace.isEmpty {
                        BarDivider()
                        ForEach(state.pinnedExtensionsInSelectedSpace) { item in
                            ExtensionButton(item: item, profile: state.selectedProfile, currentPage: { tab.browserView }, size: 16)
                        }
                    }
                    BarDivider()
                    ToolButton(symbol: "sidebar.right", help: tab.devTools == nil ? "Show DevTools" : "Hide DevTools") {
                        if tab.devTools == nil {
                            tab.browserView.showDevTools(onPanel: nil)
                        } else {
                            tab.browserView.closeDevTools()
                        }
                    }
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 10)
                .frame(height: Self.height)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .tint(.white)
        // Goes on under the page's rounded top corners, so they show the bar's color.
        .background(
            UnevenRoundedRectangle(topLeadingRadius: FLXPageCornerRadius, topTrailingRadius: FLXPageCornerRadius, style: .circular)
                .fill(barColor)
        )
    }
}

extension DeveloperBar {
    /// The space's color, darkened: at full strength it is loud for a bar this wide, and white
    /// reads better on it.
    private var barColor: Color {
        let base = NSColor(state.selectedSpace.color)
        return Color(nsColor: base.blended(withFraction: 0.3, of: .black) ?? base)
    }
}

private struct ToolButton: View {
    let symbol: String
    let help: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .help(help)
    }
}

private struct BarDivider: View {
    var body: some View {
        Rectangle().fill(.white.opacity(0.3)).frame(width: 1, height: 16).padding(.horizontal, 6)
    }
}
