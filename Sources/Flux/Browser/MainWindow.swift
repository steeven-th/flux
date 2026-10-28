import AppKit

final class MainWindow: NSWindow {
    /// Pages live in child windows that take the keyboard when clicked. AppKit asks this method,
    /// which isn't public, whether the window buttons should look active. Chromium overrides it
    /// the same way for windows whose bubbles have focus.
    @objc func hasKeyAppearance() -> Bool {
        isKeyWindow || (childWindows ?? []).contains { $0.isKeyWindow }
    }
}
