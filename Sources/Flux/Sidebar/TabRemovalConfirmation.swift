import AppKit

/// Asks before a pinned tab or a favorite is removed for good, unless the user turned it off.
@MainActor
enum TabRemovalConfirmation {
    static func confirm(_ tab: Tab, state: BrowserState) -> Bool {
        guard state.confirmsTabRemoval else { return true }
        let alert = NSAlert()
        alert.messageText = String(localized: "Close “\(tab.displayTitle)”?")
        alert.informativeText = tab.isPinned
            ? String(localized: "The tab will be removed from your pinned tabs.")
            : String(localized: "The tab will be removed from your favorites.")
        alert.addButton(withTitle: String(localized: "Close Tab"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "Don't ask again")
        let confirmed = alert.runModal() == .alertFirstButtonReturn
        if confirmed, alert.suppressionButton?.state == .on {
            state.confirmsTabRemoval = false
        }
        return confirmed
    }
}
