import AppKit

/// Whether macOS sends web links to Flux, and asking it to.
@MainActor
enum DefaultBrowser {
    static var isFlux: Bool {
        guard let url = URL(string: "https://example.com"),
              let browser = NSWorkspace.shared.urlForApplication(toOpen: url) else { return false }
        return browser.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    /// macOS asks the user to confirm. `completion` gets whether Flux is now the default.
    static func makeFlux(completion: @escaping @MainActor (Bool) -> Void) {
        let app = Bundle.main.bundleURL
        NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "http") { _ in
            Task { @MainActor in
                NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "https") { _ in
                    Task { @MainActor in completion(isFlux) }
                }
            }
        }
    }
}
