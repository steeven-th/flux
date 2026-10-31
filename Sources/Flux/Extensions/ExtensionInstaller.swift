import AppKit

/// Installs an extension in other spaces, since each profile has its own. Chromium only installs
/// from the Chrome Web Store, after asking to confirm with the permissions the extension wants, so
/// each space shows the store page in a little window, one space after another.
@MainActor
final class ExtensionInstaller {
    static let shared = ExtensionInstaller()

    private struct Install {
        let extensionID: String
        let spaceID: UUID
    }

    private var queue: [Install] = []
    private var current: (install: Install, window: LittleWindowController)?
    private weak var state: BrowserState?

    /// Asks which of the spaces without the extension should get it too.
    func ask(toInstall item: InstalledExtension, state: BrowserState, justInstalled: Bool) {
        let spaces = state.spacesWithout(extensionID: item.id)
        guard !spaces.isEmpty, let window = NSApp.windows.first(where: { $0 is MainWindow }) else { return }
        let alert = NSAlert()
        alert.messageText = justInstalled
            ? String(localized: "Install “\(item.name)” in other spaces too?")
            : String(localized: "Install “\(item.name)” in other spaces?")
        alert.informativeText = String(localized: "Each space has its own extensions. The Chrome Web Store opens in each space you choose, where you confirm the installation.")
        if let icon = item.icon { alert.icon = icon }
        let install = alert.addButton(withTitle: String(localized: "Install"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        install.isEnabled = false
        let boxes = spaces.map { space in
            NSButton(checkboxWithTitle: state.spaces(sharingProfileOf: space.id).map(\.label).joined(separator: ", "), target: nil, action: nil)
        }
        let toggle = CheckboxObserver { install.isEnabled = boxes.contains { $0.state == .on } }
        boxes.forEach {
            $0.target = toggle
            $0.action = #selector(CheckboxObserver.changed)
        }
        let stack = NSStackView(views: boxes)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.frame.size = stack.fittingSize
        alert.accessoryView = stack
        alert.beginSheetModal(for: window) { [weak self] response in
            withExtendedLifetime(toggle) {}
            guard response == .alertFirstButtonReturn else { return }
            let chosen = zip(spaces, boxes).filter { $0.1.state == .on }.map(\.0.id)
            self?.install(item.id, in: chosen, state: state)
        }
    }

    func install(_ extensionID: String, in spaceIDs: [UUID], state: BrowserState) {
        self.state = state
        queue += spaceIDs.map { Install(extensionID: extensionID, spaceID: $0) }
        if current == nil { next() }
    }

    /// True when the installation was one asked here, which then goes on to the next space.
    func didInstall(_ extensionID: String, inSpace spaceID: UUID) -> Bool {
        guard let current, current.install.extensionID == extensionID,
              let state, state.spaces(sharingProfileOf: spaceID).contains(where: { $0.id == current.install.spaceID }) else {
            return false
        }
        current.window.close()
        return true
    }

    private func next() {
        current = nil
        guard let state, !queue.isEmpty else { return }
        let install = queue.removeFirst()
        guard state.spacesWithout(extensionID: install.extensionID).contains(where: { $0.id == install.spaceID }),
              let window = LittleWindowController.show(url: Self.storePage(install.extensionID), inSpace: install.spaceID, state: state) else {
            return next()
        }
        current = (install, window)
        var asked = false
        window.model.onFinishLoading = { page in
            guard !asked else { return }
            asked = true
            Self.pressAddButton(on: page)
        }
        window.onWindowClose = { [weak self] in
            DispatchQueue.main.async { self?.next() }
        }
    }

    private static func storePage(_ extensionID: String) -> String {
        "https://chromewebstore.google.com/detail/\(extensionID)"
    }

    /// The store draws its button after the page loads, so it is looked for a few times. Its
    /// classes change, and its label is translated, so the button is the one mentioning Chrome
    /// that is closest to the extension's name. The banner asking to get Chrome is further away.
    /// Without it, the button is left to the user.
    private static func pressAddButton(on page: FLXBrowserView, attempts: Int = 20) {
        let script = """
            (() => {
              const title = document.querySelector('h1');
              if (!title) return false;
              const distance = button => {
                let steps = 0;
                for (let element = button; element; element = element.parentElement, steps++) {
                  if (element.contains(title)) return steps;
                }
                return Infinity;
              };
              const button = [...document.querySelectorAll('button')]
                .filter(button => button.offsetParent && /chrome/i.test(button.textContent))
                .sort((a, b) => distance(a) - distance(b))[0];
              if (!button) return false;
              button.click();
              return true;
            })()
            """
        // The store only installs on a click, which DevTools can make count as one.
        page.sendDevToolsMethod("Runtime.evaluate", params: ["expression": script, "userGesture": true, "returnByValue": true]) { result in
            let pressed = (result?["result"] as? [String: Any])?["value"] as? Bool == true
            guard !pressed, attempts > 1 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pressAddButton(on: page, attempts: attempts - 1)
            }
        }
    }
}

private final class CheckboxObserver: NSObject {
    let onChange: () -> Void

    init(_ onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    @objc func changed() {
        onChange()
    }
}
