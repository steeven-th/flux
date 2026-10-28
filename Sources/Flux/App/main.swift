import AppKit

MainActor.assumeIsolated {
    // Chromium expects its NSApplication subclass to exist before it initializes.
    let app = FLXApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate

    guard FLXEngine.start(withRootCachePath: AppPaths.chromiumRoot.path) else {
        exit(1)
    }
    withExtendedLifetime(delegate) {
        FLXEngine.runMessageLoop()
    }
    FLXEngine.shutdown()
}
