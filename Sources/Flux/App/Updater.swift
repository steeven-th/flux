import AppKit
import Sparkle

/// Checks flux-browser.com for new versions with Sparkle. A version found by the daily check waits
/// in the Flux menu, as in Arc, instead of opening a window over the page.
@MainActor
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController!
    /// The Flux menu's Check for Updates item, which becomes Update Available.
    weak var menuItem: NSMenuItem?

    override init() {
        super.init()
        // A development build would replace itself with the released version.
        #if DEBUG
        let starts = false
        #else
        let starts = true
        #endif
        controller = SPUStandardUpdaterController(startingUpdater: starts, updaterDelegate: nil, userDriverDelegate: self)
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    private func showUpdateAvailable(_ available: Bool) {
        menuItem?.title = available ? String(localized: "Update Available…") : String(localized: "Check for Updates…")
        menuItem?.badge = available ? .updates(count: 1) : nil
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        MainActor.assumeIsolated { showUpdateAvailable(!handleShowingUpdate) }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { showUpdateAvailable(false) }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { showUpdateAvailable(false) }
    }
}
