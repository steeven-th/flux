import AppKit

/// Chromium draws some of its dialogs (the extension install prompt, for one) in titled windows
/// whose title bar covers the top of their content. This makes those title bars transparent.
@MainActor
final class ChromiumDialogFixer {
    private var seen = Set<ObjectIdentifier>()
    private var observers: [NSObjectProtocol] = []

    init() {
        // These windows don't always become key. A window that appears on screen changes its
        // occlusion state, so that is watched too.
        let names = [NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scanWindows() }
            }
        }
    }

    private func scanWindows() {
        for window in NSApp.windows where window.isVisible {
            guard seen.insert(ObjectIdentifier(window)).inserted else { continue }
            let isChromiumWindow = String(describing: type(of: window)).contains("NativeWidget")
            if isChromiumWindow, window.styleMask.contains(.titled) {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
            }
        }
    }
}
