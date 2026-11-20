import AppKit

/// A window that takes its space's appearance. Child windows don't inherit their parent's, and
/// pages, the sidebar overlay, Peek and the find bar are all child windows.
class SpaceWindow: NSWindow {
    override var appearance: NSAppearance? {
        didSet { childWindows?.forEach { $0.appearance = appearance } }
    }

    override func addChildWindow(_ childWin: NSWindow, ordered place: NSWindow.OrderingMode) {
        childWin.appearance = appearance
        super.addChildWindow(childWin, ordered: place)
    }
}
