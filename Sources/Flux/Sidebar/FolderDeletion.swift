import AppKit

/// A folder with tabs asks whether they go too. An empty one goes at once.
@MainActor
enum FolderDeletion {
    static func ask(_ folder: Folder, state: BrowserState) {
        let count = state.tabCount(in: folder)
        guard count > 0 else { return state.delete(folder) }
        let alert = NSAlert()
        alert.messageText = String(localized: "Delete “\(folder.title)”?")
        alert.informativeText = String(localized: "It holds \(count) tabs. They can go with it, or stay in its place.")
        alert.addButton(withTitle: String(localized: "Delete Folder and Tabs"))
        alert.addButton(withTitle: String(localized: "Keep the Tabs"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons[0].hasDestructiveAction = true
        switch alert.runModal() {
        case .alertFirstButtonReturn: state.deleteWithContents(folder)
        case .alertSecondButtonReturn: state.delete(folder)
        default: break
        }
    }
}
