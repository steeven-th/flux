import SwiftUI

/// The bar over a pane: the developer bar on sites in developer mode, a light one otherwise.
/// Single pages only have the developer bar.
struct PaneHeader: View {
    let state: BrowserState
    let tab: Tab

    var body: some View {
        if state.isDeveloperMode(for: tab.url) {
            DeveloperBar(state: state, tab: tab)
        } else {
            PaneBar(state: state, tab: tab)
        }
    }
}

/// The bar over a page whose site is in developer mode: its full address, and tools at hand.
struct DeveloperBar: View {
    let state: BrowserState
    let tab: Tab

    static let height: CGFloat = 36

    var body: some View {
        let isInSplit = state.split(of: tab) != nil
        HStack(spacing: 2) {
            Image(systemName: URL(string: tab.url)?.scheme == "https" ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 11))
                .padding(.trailing, 4)
            DeveloperAddressField(state: state, tab: tab)
            Spacer(minLength: 12)
            CopyLinkButton(url: tab.url).modifier(BarHighlight())
            BarDivider()
            ToolButton(symbol: "camera", help: "Capture an Area") { PageCapture.captureArea(of: tab, state: state) }
            ToolButton(symbol: "text.viewfinder", help: "Capture the Whole Page") { PageCapture.captureWholePage(of: tab, state: state) }
            let tools = state.devToolsInBar
            if !tools.isEmpty {
                BarDivider()
                ForEach(tools) { tool in
                    ToolButton(symbol: tool.symbol, help: LocalizedStringKey(tool.name)) { tab.show(tool) }
                }
            }
            if !state.pinnedExtensionsInSelectedSpace.isEmpty {
                BarDivider()
                ForEach(state.pinnedExtensionsInSelectedSpace) { item in
                    ExtensionButton(item: item, profile: state.selectedProfile, currentPage: { tab.browserView }, size: 16)
                        .modifier(BarHighlight())
                }
            }
            BarDivider()
            if tab.translation != nil {
                TranslationButton(tab: tab).modifier(BarHighlight())
            }
            SplitMenuButton(state: state, tab: tab).modifier(BarHighlight())
            ToolButton(symbol: "sidebar.right", help: tab.devTools == nil ? "Show DevTools" : "Hide DevTools", isOn: tab.devTools != nil) {
                if tab.devTools == nil {
                    tab.browserView.showDevTools(onPanel: nil)
                } else {
                    tab.browserView.closeDevTools()
                }
            }
            if isInSplit {
                ToolButton(symbol: "xmark", help: "Close") { state.closePane(tab) }
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .tint(.white)
        // Some symbols would fill their shapes in their own preferred mode.
        .symbolRenderingMode(.monochrome)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: FLXPageCornerRadius, topTrailingRadius: FLXPageCornerRadius, style: .circular)
                .fill(barColor)
        )
    }
}

/// The full address, edited in place as in Arc's developer mode, where changing a parameter of
/// the address is common.
private struct DeveloperAddressField: View {
    let state: BrowserState
    let tab: Tab
    @State private var text = ""
    @State private var editor: (view: NSTextView, attributes: [NSAttributedString.Key: Any])?
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .lineLimit(1)
            .focused($isFocused)
            .onAppear { text = tab.url }
            .onChange(of: tab.url) { if !isFocused { text = tab.url } }
            .onChange(of: isFocused) {
                if isFocused {
                    DispatchQueue.main.async {
                        // A click puts the caret where it lands. The whole address is selected
                        // instead, as in the address bars of browsers.
                        NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                        // The bar's white tint makes the selection white, under white text. The
                        // window shares this editor with its other fields, so it gets its colors
                        // back afterwards.
                        guard let view = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
                        editor = (view, view.selectedTextAttributes)
                        view.selectedTextAttributes = [.backgroundColor: NSColor.white, .foregroundColor: NSColor.black]
                    }
                } else {
                    text = tab.url
                    if let editor { editor.view.selectedTextAttributes = editor.attributes }
                    editor = nil
                }
            }
            .onSubmit {
                let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !input.isEmpty else { return }
                tab.load(BrowserState.looksLikeURL(input) ? BrowserState.normalizedURL(input) : state.searchEngine.url(for: input))
                tab.browserView.focus()
            }
            .onExitCommand {
                text = tab.url
                tab.browserView.focus()
            }
    }
}

/// The bar over a pane of a split, like Arc's: navigation, the site, and the pane's actions.
struct PaneBar: View {
    let state: BrowserState
    let tab: Tab

    var body: some View {
        ZStack {
            HStack(spacing: 2) {
                PaneButton(symbol: "chevron.left", help: "Back") { tab.goBack() }
                    .disabled(!tab.canGoBack)
                PaneButton(symbol: "chevron.right", help: "Forward") { tab.goForward() }
                    .disabled(!tab.canGoForward)
                PaneButton(symbol: "arrow.clockwise", help: "Reload Page") { tab.browserView.reload() }
                Spacer()
                ForEach(state.pinnedExtensionsInSelectedSpace) { item in
                    ExtensionButton(item: item, profile: state.selectedProfile, currentPage: { tab.browserView }, size: 14)
                }
                TranslationButton(tab: tab)
                SplitMenuButton(state: state, tab: tab)
                PaneButton(symbol: "xmark", help: "Close") { state.closePane(tab) }
            }
            // Opens the command bar on this pane's page, like the sidebar's address does.
            Button {
                state.select(tab)
                (NSApp.delegate as? AppDelegate)?.openLocation(nil)
            } label: {
                Text(verbatim: URL(string: tab.url)?.host() ?? tab.url)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: 260, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .symbolRenderingMode(.monochrome)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: FLXPageCornerRadius, topTrailingRadius: FLXPageCornerRadius, style: .circular)
                .fill(.background)
        )
    }
}

private struct PaneButton: View {
    let symbol: String
    let help: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .help(help)
    }
}

/// Arc's split menu: moving the pane, adding one beside it, leaving the split.
struct SplitMenuButton: View {
    let state: BrowserState
    let tab: Tab

    var body: some View {
        let split = state.split(of: tab)
        let panes = split.map(state.panes(of:)) ?? [tab]
        let index = panes.firstIndex { $0 === tab } ?? 0
        let isVertical = split?.isVertical ?? false
        let canAdd = panes.count < BrowserState.maxSplitPanes && !tab.isPinned
        Menu {
            if split != nil {
                Button(isVertical ? "Move Up" : "Move Left") { state.movePane(tab, by: -1) }
                    .disabled(index == 0)
                Button(isVertical ? "Move Down" : "Move Right") { state.movePane(tab, by: 1) }
                    .disabled(index == panes.count - 1)
                Divider()
            }
            Button(isVertical ? "Add Split Below" : "Add Right Split") { addPane(after: true) }
                .disabled(!canAdd)
            Button(isVertical ? "Add Split Above" : "Add Left Split") { addPane(after: false) }
                .disabled(!canAdd)
            if let split {
                Divider()
                Button("Separate Tab from Split") { state.removeFromSplit(tab) }
                Button(isVertical ? "Convert to Horizontal Split View" : "Convert to Vertical Split View") {
                    state.toggleOrientation(split)
                }
            }
        } label: {
            Image(systemName: isVertical ? "rectangle.split.1x2" : "rectangle.split.2x1")
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Split View")
    }

    private func addPane(after: Bool) {
        state.select(tab)
        (NSApp.delegate as? AppDelegate)?.showSplitPaneCommandBar(after: after)
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
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .help(help)
        .modifier(BarHighlight(isOn: isOn))
    }
}

/// Every button of the bar lights up under the pointer, and stays lit while what it turns on is on.
private struct BarHighlight: ViewModifier {
    var isOn = false

    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(isOn ? 0.25 : isHovered ? 0.12 : 0)))
            .onHover { isHovered = $0 }
    }
}

private struct BarDivider: View {
    var body: some View {
        Rectangle().fill(.white.opacity(0.3)).frame(width: 1, height: 16).padding(.horizontal, 6)
    }
}
