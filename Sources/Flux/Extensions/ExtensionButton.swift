import SwiftUI

/// An extension's icon. Clicking it runs its action on the current page.
struct ExtensionButton: View {
    let item: InstalledExtension
    let profile: FLXProfile
    /// The page the action applies to.
    let currentPage: () -> FLXBrowserView?
    var size: CGFloat = 18

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
            .frame(width: size, height: size)
            .padding(5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(item.name)
        .disabled(item.popupURL == nil && !ToolbarActionRunner.shared.isAvailable)
        .background(AnchorReader(view: anchor))
    }

    /// Popups open in Flux's own panel, which shows at once. Extensions without one get Chrome's
    /// toolbar action.
    private func run() async {
        if let url = item.popupURL {
            ExtensionPopupPanel.show(url: url, profile: profile, below: anchor)
        } else if let page = currentPage() {
            await ToolbarActionRunner.shared.run(item.id, on: page, below: anchor)
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
