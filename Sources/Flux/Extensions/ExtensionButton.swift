import SwiftUI

/// An extension's icon. Clicking it runs its action on the current page.
struct ExtensionButton: View {
    let item: InstalledExtension
    let profile: FLXProfile
    /// The page the action applies to.
    let currentPage: () -> FLXBrowserView?
    var size: CGFloat = 18

    @State private var anchor = AnchorView()
    /// Changes when an extension changes its button, so the badge is read again.
    @State private var revision = 0

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
            .overlay(alignment: .bottomTrailing) { badge }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(item.name)
        .background(AnchorReader(view: anchor))
        .onReceive(NotificationCenter.default.publisher(for: ExtensionButton.actionsDidChange)) { _ in revision += 1 }
    }

    static let actionsDidChange = Notification.Name("ExtensionActionsDidChange")

    @ViewBuilder private var badge: some View {
        let _ = revision
        if let page = currentPage(), let text = profile.badgeText(forExtension: item.id, onPage: page) {
            Text(text)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 3)
                .frame(minWidth: 12, minHeight: 11)
                .background(Color(nsColor: profile.badgeColor(forExtension: item.id, onPage: page) ?? .systemRed), in: Capsule())
                .fixedSize()
        }
    }

    private func run() async {
        guard let page = currentPage(), let popup = profile.runAction(forExtension: item.id, onPage: page) else { return }
        ExtensionPopupPanel.show(popup, below: anchor)
    }
}

/// An AppKit view laid out behind a SwiftUI view, to know where that view is on screen.
final class AnchorView: NSView {}

private struct AnchorReader: NSViewRepresentable {
    let view: AnchorView

    func makeNSView(context: Context) -> AnchorView { view }
    func updateNSView(_ nsView: AnchorView, context: Context) {}
}
