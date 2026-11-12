import AppKit

MainActor.assumeIsolated {
    FLXDevTools.reservePipe()
    let database = Result { try AppDatabase(url: AppPaths.database) }
    // Profiles of deleted spaces go before Chromium opens them.
    try? database.get().deletePendingProfileFolders()

    let delegate = AppDelegate(database: database)
    FLXEngine.start(withRootCachePath: AppPaths.chromiumRoot.path) {
        delegate.start()
    }
}
