import AppKit

MainActor.assumeIsolated {
    // Chromium expects its NSApplication subclass to exist before it initializes.
    let app = FLXApplication.shared
    let database = Result { try AppDatabase(url: AppPaths.database) }
    // Profiles of deleted spaces go before Chromium opens them.
    try? database.get().deletePendingProfileFolders()

    let delegate = AppDelegate(database: database)
    app.delegate = delegate

    guard FLXEngine.start(withRootCachePath: AppPaths.chromiumRoot.path) else {
        exit(1)
    }
    withExtendedLifetime(delegate) {
        FLXEngine.runMessageLoop()
    }
    FLXEngine.shutdown()
}
