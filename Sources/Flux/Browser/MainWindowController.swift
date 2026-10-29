import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController {
    private static let sidebarWidth: CGFloat = 260
    private static let pageMargin: CGFloat = 8

    private let state: BrowserState
    private let pageContainer = NSView()

    init(state: BrowserState) {
        self.state = state
        let window = MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()
        super.init(window: window)

        let background = NSHostingView(rootView: SpaceBackground(state: state))
        let sidebar = NSHostingView(rootView: SidebarView(state: state) { [weak self] target in self?.showCommandBar(target) })
        for view in [background, sidebar, pageContainer] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }

        let content = NSView()
        content.addSubview(background)
        content.addSubview(sidebar)
        content.addSubview(pageContainer)
        window.contentView = content
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            background.topAnchor.constraint(equalTo: content.topAnchor),
            background.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: Self.sidebarWidth),
            // The page sits in its own window above this one, so the title bar doesn't cover it.
            pageContainer.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            pageContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.pageMargin),
            pageContainer.topAnchor.constraint(equalTo: content.topAnchor, constant: Self.pageMargin),
            pageContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Self.pageMargin),
        ])

        showSelectedTab()
        observeSelectedTab()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not available")
    }

    func showCommandBar(_ target: CommandBarModel.Target) {
        guard let window else { return }
        CommandBarPanel.show(target, state: state, over: window)
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
        selected.focus()
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
