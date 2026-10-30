import AppKit
import SwiftUI

/// Shown at the first launch, before Flux has any space.
@MainActor
final class WelcomeWindowController: NSWindowController {
    init(onFinish: @escaping (WelcomeModel) -> Void) {
        let model = WelcomeModel()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = NSHostingView(rootView: WelcomeView(
            model: model,
            finish: { onFinish(model) }
        ))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not available")
    }
}
