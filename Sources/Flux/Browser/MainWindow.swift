import AppKit

final class MainWindow: NSWindow {
    /// Pages live in child windows that take the keyboard when clicked. AppKit asks this method,
    /// which isn't public, whether the window buttons should look active. Chromium overrides it
    /// the same way for windows whose bubbles have focus.
    @objc func hasKeyAppearance() -> Bool {
        isKeyWindow || (childWindows ?? []).contains { $0.isKeyWindow }
    }
}

extension MainWindow {
    /// The main window with the keyboard, its pages' included, or the frontmost one.
    static var active: MainWindow? {
        let key = NSApp.keyWindow.flatMap { window in sequence(first: window, next: \.parent).first { $0 is MainWindow } }
        return (key ?? NSApp.orderedWindows.first { $0 is MainWindow }) as? MainWindow
    }
}
