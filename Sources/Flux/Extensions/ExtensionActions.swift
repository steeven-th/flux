import AppKit

/// Runs an extension's toolbar action on a page, as a click on its button in Chrome's toolbar
/// would. Used for extensions without a popup, which only react to chrome.action.onClicked: Chrome
/// shows its own popups only after a couple of seconds when its toolbar is hidden, so Flux opens
/// popups itself. Uses the protocol's Extensions.triggerAction, which takes the page's tab target.
@MainActor
final class ExtensionActions {
    static let shared = ExtensionActions()

    private enum Failure: Error {
        case protocolError(String)
        case noTabTarget
    }

    private struct CachedTarget {
        weak var page: FLXBrowserView?
        let tabTarget: String
    }

    private var tabTargets: [ObjectIdentifier: CachedTarget] = [:]
    /// Sessions attached to a tab target, waiting for the page target that attaches under it.
    private var pageWaiters: [String: (String?) -> Void] = [:]

    private init() {
        FLXDevTools.eventHandler = { [weak self] method, params, sessionID in
            MainActor.assumeIsolated { self?.handleEvent(method, params: params, sessionID: sessionID) }
        }
    }

    var isAvailable: Bool {
        FLXDevTools.isAvailable
    }

    /// Called with the page an extension's side panel shows for a page, once its action asked for
    /// one. Chrome shows side panels in its own window, which Flux hides.
    var onSidePanel: ((FLXBrowserView, String) -> Void)?

    /// Returns false when the action couldn't run.
    @discardableResult
    func run(_ extensionID: String, on page: FLXBrowserView, below anchor: NSView) async -> Bool {
        guard isAvailable else { return false }
        do {
            let tab = try await tabTarget(for: page)
            let before = visibleWindows()
            _ = try await call("Extensions.triggerAction", ["id": extensionID, "targetId": tab])
            ExtensionPopupPlacement.place(appearingAfter: before, below: anchor)
            // The action sets its panel up as it runs.
            try? await Task.sleep(for: .milliseconds(400))
            if let path = await sidePanelPath(extensionID, for: page.currentURL) {
                onSidePanel?(page, "chrome-extension://\(extensionID)/\(path)")
            }
            return true
        } catch {
            tabTargets[ObjectIdentifier(page)] = nil
            return false
        }
    }

    /// Asks the extension's service worker which page its side panel shows for the tab showing
    /// `url`: extensions choose it as their action runs, with chrome.sidePanel.setOptions.
    private func sidePanelPath(_ extensionID: String, for url: String) async -> String? {
        guard let targets = try? await call("Target.getTargets")["targetInfos"] as? [[String: Any]],
              let worker = targets.first(where: {
                  $0["type"] as? String == "service_worker" && ($0["url"] as? String)?.hasPrefix("chrome-extension://\(extensionID)/") == true
              })?["targetId"] as? String,
              let session = try? await call("Target.attachToTarget", ["targetId": worker, "flatten": true])["sessionId"] as? String
        else { return nil }
        defer { Task { _ = try? await call("Target.detachFromTarget", ["sessionId": session]) } }
        let urlJSON = String(decoding: (try? JSONSerialization.data(withJSONObject: [url])) ?? Data("[\"\"]".utf8), as: UTF8.self)
        let script = """
            (async () => {
              if (!chrome.sidePanel) return null;
              const url = \(urlJSON)[0];
              for (const tab of await chrome.tabs.query({})) {
                if (tab.url !== url) continue;
                const options = await chrome.sidePanel.getOptions({ tabId: tab.id });
                if (options.enabled !== false && options.path) return options.path;
              }
              const fallback = await chrome.sidePanel.getOptions({});
              return fallback.enabled !== false && fallback.path ? fallback.path : null;
            })()
            """
        let result = try? await call("Runtime.evaluate", ["expression": script, "awaitPromise": true, "returnByValue": true], session: session)
        return (result?["result"] as? [String: Any])?["value"] as? String
    }

    private func visibleWindows() -> Set<ObjectIdentifier> {
        Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
    }

    /// The protocol has no direct link from a page to its tab, so each tab target is attached in
    /// turn until the page auto-attaches under one of them. The result is cached per page.
    private func tabTarget(for page: FLXBrowserView) async throws -> String {
        if let cached = tabTargets[ObjectIdentifier(page)], cached.page === page {
            return cached.tabTarget
        }
        let pageID: String? = await withCheckedContinuation { continuation in
            page.devToolsTargetID { continuation.resume(returning: $0) }
        }
        guard let pageID else { throw Failure.noTabTarget }
        let tabs = (try await call("Target.getTargets", ["filter": [["type": "tab"]]])["targetInfos"] as? [[String: Any]]) ?? []
        // Tabs showing the same URL are the likely ones, so they're tried first.
        let url = page.currentURL
        let ordered = tabs.filter { $0["url"] as? String == url } + tabs.filter { $0["url"] as? String != url }
        for tab in ordered {
            guard let tabID = tab["targetId"] as? String else { continue }
            if try await pageTarget(inTab: tabID) == pageID {
                tabTargets[ObjectIdentifier(page)] = CachedTarget(page: page, tabTarget: tabID)
                return tabID
            }
        }
        throw Failure.noTabTarget
    }

    private func pageTarget(inTab tabID: String) async throws -> String? {
        let attached = try await call("Target.attachToTarget", ["targetId": tabID, "flatten": true])
        guard let session = attached["sessionId"] as? String else { return nil }
        let page: String? = await withCheckedContinuation { continuation in
            pageWaiters[session] = { continuation.resume(returning: $0) }
            Task {
                _ = try? await self.call(
                    "Target.setAutoAttach",
                    ["autoAttach": true, "waitForDebuggerOnStart": false, "flatten": true],
                    session: session
                )
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                MainActor.assumeIsolated { self?.pageWaiters.removeValue(forKey: session)?(nil) }
            }
        }
        _ = try? await call("Target.detachFromTarget", ["sessionId": session])
        return page
    }

    private func handleEvent(_ method: String, params: [String: Any], sessionID: String?) {
        guard method == "Target.attachedToTarget", let sessionID, pageWaiters[sessionID] != nil,
              let info = params["targetInfo"] as? [String: Any], info["type"] as? String == "page" else { return }
        pageWaiters.removeValue(forKey: sessionID)?(info["targetId"] as? String)
    }

    /// Protocol replies are plain JSON values, delivered on the main thread.
    private struct Reply: @unchecked Sendable {
        let value: [String: Any]
    }

    private func call(_ method: String, _ params: [String: Any] = [:], session: String? = nil) async throws -> [String: Any] {
        let reply: Reply = try await withCheckedThrowingContinuation { continuation in
            FLXDevTools.sendMethod(method, params: params, sessionID: session) { result, error in
                if let result {
                    continuation.resume(returning: Reply(value: result))
                } else {
                    continuation.resume(throwing: Failure.protocolError(error ?? method))
                }
            }
        }
        return reply.value
    }
}

/// Chrome hangs an extension's popup from its own toolbar, which Flux hides. The popup's window is
/// moved under the button that was clicked, and kept there as the popup resizes to its content.
@MainActor
enum ExtensionPopupPlacement {
    private static var observers: [ObjectIdentifier: [NSObjectProtocol]] = [:]

    static func place(appearingAfter before: Set<ObjectIdentifier>, below anchor: NSView, attempt: Int = 0) {
        guard let anchorWindow = anchor.window else { return }
        let anchorFrame = anchorWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let topLeft = NSPoint(x: anchorFrame.minX, y: anchorFrame.minY - 6)

        // Chrome's popup is a borderless window. An extension opening a window of its own is titled.
        let popup = NSApp.windows.first { window in
            !before.contains(ObjectIdentifier(window)) && window.isVisible && window.frame.width > 1
                && !window.styleMask.contains(.titled) && !(window is NSPanel)
        }
        guard let popup else {
            // The popup shows once its page has loaded. Actions without a popup never show one.
            guard attempt < 60 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                MainActor.assumeIsolated { place(appearingAfter: before, below: anchor, attempt: attempt + 1) }
            }
            return
        }
        keep(popup, topLeft: topLeft)
    }

    private static func move(_ popup: NSWindow, topLeft: NSPoint) {
        let origin = NSPoint(x: topLeft.x, y: topLeft.y - popup.frame.height)
        if popup.frame.origin != origin { popup.setFrameOrigin(origin) }
    }

    private static func keep(_ popup: NSWindow, topLeft: NSPoint) {
        let id = ObjectIdentifier(popup)
        move(popup, topLeft: topLeft)
        let center = NotificationCenter.default
        var tokens = [NSWindow.didResizeNotification, NSWindow.didMoveNotification].map { name in
            center.addObserver(forName: name, object: popup, queue: .main) { _ in
                MainActor.assumeIsolated { move(popup, topLeft: topLeft) }
            }
        }
        tokens.append(center.addObserver(forName: NSWindow.willCloseNotification, object: popup, queue: .main) { _ in
            MainActor.assumeIsolated {
                observers.removeValue(forKey: id)?.forEach(center.removeObserver)
            }
        })
        observers[id] = tokens
    }
}
