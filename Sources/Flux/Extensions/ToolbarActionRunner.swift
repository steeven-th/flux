import AppKit

/// Runs an extension's toolbar action on a page, as a click on its button in Chrome's toolbar
/// would. Extensions without a popup only react to chrome.action.onClicked, which only Chrome
/// sends. Flux opens popups itself, since Chrome shows them a couple of seconds late when its
/// toolbar is hidden.
@MainActor
final class ToolbarActionRunner {
    static let shared = ToolbarActionRunner()

    /// Called with the page an extension's side panel shows next to a page, once its action asked
    /// for one. Chrome shows side panels in its own window, which Flux hides.
    var onSidePanel: ((FLXBrowserView, String) -> Void)?

    private let connection = DevToolsConnection.browser
    private lazy var tabTargets = TabTargets(connection: connection)

    var isAvailable: Bool {
        connection.isAvailable
    }

    /// Returns false when the action couldn't run.
    @discardableResult
    func run(_ extensionID: String, on page: FLXBrowserView, below anchor: NSView) async -> Bool {
        guard isAvailable else { return false }
        let popupWatcher = PopupWindowWatcher(anchor: anchor)
        do {
            let tabID = try await tabTargets.tabID(holding: page)
            _ = try await connection.send("Extensions.triggerAction", ["id": extensionID, "targetId": tabID])
        } catch {
            tabTargets.forget(page)
            return false
        }
        popupWatcher.start()
        // The action sets its side panel up as it runs.
        try? await Task.sleep(for: .milliseconds(400))
        if let path = await SidePanelLookup(connection: connection).path(of: extensionID, forPageAt: page.currentURL) {
            onSidePanel?(page, "chrome-extension://\(extensionID)/\(path)")
        }
        return true
    }
}

/// Asks an extension's service worker which page its side panel shows next to a page. Extensions
/// choose it as their action runs, with chrome.sidePanel.setOptions.
@MainActor
struct SidePanelLookup {
    let connection: DevToolsConnection

    func path(of extensionID: String, forPageAt url: String) async -> String? {
        guard let reply = try? await connection.send("Target.getTargets"),
              let worker = (reply["targetInfos"] as? [[String: Any]])?.first(where: {
                  $0["type"] as? String == "service_worker"
                      && ($0["url"] as? String)?.hasPrefix("chrome-extension://\(extensionID)/") == true
              })?["targetId"] as? String,
              let attached = try? await connection.send("Target.attachToTarget", ["targetId": worker, "flatten": true]),
              let session = attached["sessionId"] as? String
        else { return nil }
        defer { Task { [connection] in _ = try? await connection.send("Target.detachFromTarget", ["sessionId": session]) } }
        let quotedURL = String(decoding: (try? JSONSerialization.data(withJSONObject: [url])) ?? Data("[\"\"]".utf8), as: UTF8.self)
        let script = """
            (async () => {
              if (!chrome.sidePanel) return null;
              const url = \(quotedURL)[0];
              for (const tab of await chrome.tabs.query({})) {
                if (tab.url !== url) continue;
                const options = await chrome.sidePanel.getOptions({ tabId: tab.id });
                if (options.enabled !== false && options.path) return options.path;
              }
              const fallback = await chrome.sidePanel.getOptions({});
              return fallback.enabled !== false && fallback.path ? fallback.path : null;
            })()
            """
        let result = try? await connection.send(
            "Runtime.evaluate", ["expression": script, "awaitPromise": true, "returnByValue": true], in: session
        )
        return (result?["result"] as? [String: Any])?["value"] as? String
    }
}
