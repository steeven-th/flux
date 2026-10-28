import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController {
    private static let sidebarWidth: CGFloat = 260

    private let state: BrowserState
    private let pageContainer = NSView()

    init(state: BrowserState) {
        self.state = state
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()
        super.init(window: window)

        let sidebar = NSHostingView(rootView: SidebarView(state: state))
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        pageContainer.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(sidebar)
        content.addSubview(pageContainer)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: Self.sidebarWidth),
            pageContainer.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            pageContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            pageContainer.topAnchor.constraint(equalTo: content.topAnchor),
            pageContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content

        showSelectedTab()
        observeSelectedTab()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not available")
    }

    /// Pages of other tabs stay alive. Only the selected one is in the view hierarchy.
    private func showSelectedTab() {
        let selected = state.selectedTab?.browserView
        for view in pageContainer.subviews where view !== selected {
            view.removeFromSuperview()
        }
        guard let selected, selected.superview !== pageContainer else { return }
        selected.frame = pageContainer.bounds
        selected.autoresizingMask = [.width, .height]
        pageContainer.addSubview(selected)
        window?.makeFirstResponder(selected)
    }

    private func observeSelectedTab() {
        withObservationTracking {
            _ = state.selectedTab
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.showSelectedTab()
                self?.observeSelectedTab()
            }
        }
    }
}
