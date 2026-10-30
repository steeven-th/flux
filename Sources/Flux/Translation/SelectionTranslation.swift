import SwiftUI
import Translation

/// The system's translation popover for text picked in a page, the one Safari shows. It needs a
/// SwiftUI view to point at, so a tiny panel stands where the menu was opened.
@MainActor
enum SelectionTranslation {
    private static var panel: NSPanel?

    static func show(_ text: String, at point: NSPoint) {
        close()
        let panel = AnchorPanel(contentRect: NSRect(x: point.x, y: point.y, width: 1, height: 1),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: Anchor(text: text) { close() })
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    private static func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

/// Borderless panels can't be key otherwise, and the popover's buttons would not respond.
private final class AnchorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct Anchor: View {
    let text: String
    let onClose: () -> Void

    @State private var isPresented = false

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationPresentation(isPresented: $isPresented, text: text)
            .onAppear { isPresented = true }
            .onChange(of: isPresented) { if !isPresented { onClose() } }
    }
}
