import SwiftUI

/// The icons of the selected space's extensions. Clicking one runs its action on the current page.
struct ExtensionsBar: View {
    let extensions: [InstalledExtension]
    let profile: FLXProfile
    /// The page the actions apply to.
    let currentPage: () -> FLXBrowserView?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(extensions) { item in
                ExtensionButton(item: item, profile: profile, currentPage: currentPage)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ExtensionButton: View {
    let item: InstalledExtension
    let profile: FLXProfile
    let currentPage: () -> FLXBrowserView?

    @State private var anchor = AnchorView()

    var body: some View {
        Button {
            Task { await run() }
        } label: {
            Group {
                if let icon = item.icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "puzzlepiece.extension")
                }
            }
            .frame(width: 18, height: 18)
            .padding(5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(item.name)
        .disabled(item.popupURL == nil && !ExtensionActions.shared.isAvailable)
        .background(AnchorReader(view: anchor))
    }

    /// Popups open in Flux's own panel, which shows at once. Extensions without one get Chrome's
    /// toolbar action.
    private func run() async {
        if let url = item.popupURL {
            ExtensionPopupPanel.show(url: url, profile: profile, below: anchor)
        } else if let page = currentPage() {
            await ExtensionActions.shared.run(item.id, on: page, below: anchor)
        }
    }
}

/// An AppKit view laid out behind a SwiftUI view, to know where that view is on screen.
final class AnchorView: NSView {}

private struct AnchorReader: NSViewRepresentable {
    let view: AnchorView

    func makeNSView(context: Context) -> AnchorView { view }
    func updateNSView(_ nsView: AnchorView, context: Context) {}
}
