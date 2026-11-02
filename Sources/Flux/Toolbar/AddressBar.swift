import SwiftUI

/// The selected tab's site. Clicking it opens the command bar to go elsewhere, like in Arc. While
/// the pointer is on the sidebar, it also shows the pinned extensions, copying the link and the
/// page's options.
struct AddressBar: View {
    @Bindable var state: BrowserState
    let isSidebarHovered: Bool
    let showCommandBar: () -> Void

    @State private var showsOptions = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: showCommandBar) {
                Text(text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)

            if let tab = state.selectedTab {
                ZoomButton(state: state, tab: tab)
                TranslationButton(tab: tab)
            }

            if let tab = state.selectedTab, isSidebarHovered || showsOptions {
                ForEach(state.pinnedExtensionsInSelectedSpace) { item in
                    ExtensionButton(item: item, profile: state.selectedProfile, currentPage: { tab.browserView }, size: 16)
                }
                CopyLinkButton(url: tab.url)
                Button {
                    showsOptions.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Options for This Page")
                .popover(isPresented: $showsOptions, arrowEdge: .bottom) {
                    PageOptions(state: state, tab: tab) { showsOptions = false }
                }
            }
        }
        .padding(.trailing, 3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.06)))
    }

    private var text: String {
        guard let url = state.selectedTab?.url else { return String(localized: "Search or Enter URL") }
        guard let host = URL(string: url)?.host() else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// Copies the page's address, then shows a check mark for a moment.
struct CopyLinkButton: View {
    let url: String

    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(copied ? "Copied" : "Copy Link")
    }
}

/// Shows the page's zoom when it isn't 100 %, and puts it back.
private struct ZoomButton: View {
    let state: BrowserState
    let tab: Tab

    var body: some View {
        if abs(tab.zoomFactor - 1) > 0.001 {
            Button {
                tab.zoom(.reset)
                state.tabs.forEach { $0.refreshZoom() }
            } label: {
                Text(tab.zoomFactor, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Reset Zoom")
        }
    }
}
