import Foundation

/// The tab target holding each page. Some protocol methods, Extensions.triggerAction among them,
/// want the tab rather than the page, and the protocol doesn't link one to the other: each tab is
/// attached with auto-attach on, until the page attaches under it.
@MainActor
final class TabTargets {
    private struct Found {
        weak var page: FLXBrowserView?
        let tabID: String
    }

    private enum Failure: Error {
        case notFound
    }

    private let connection: DevToolsConnection
    private var found: [ObjectIdentifier: Found] = [:]

    init(connection: DevToolsConnection) {
        self.connection = connection
    }

    func tabID(holding page: FLXBrowserView) async throws -> String {
        if let known = found[ObjectIdentifier(page)], known.page === page {
            return known.tabID
        }
        let pageID: String? = await withCheckedContinuation { continuation in
            page.devToolsTargetID { continuation.resume(returning: $0) }
        }
        guard let pageID else { throw Failure.notFound }
        let reply = try await connection.send("Target.getTargets", ["filter": [["type": "tab"]]])
        let url = page.currentURL
        // A tab showing the page's URL is most likely the one.
        let tabs = ((reply["targetInfos"] as? [[String: Any]]) ?? [])
            .sorted { ($0["url"] as? String == url ? 0 : 1) < ($1["url"] as? String == url ? 0 : 1) }
            .compactMap { $0["targetId"] as? String }
        for tabID in tabs where await childPageID(of: tabID) == pageID {
            found[ObjectIdentifier(page)] = Found(page: page, tabID: tabID)
            return tabID
        }
        throw Failure.notFound
    }

    func forget(_ page: FLXBrowserView) {
        found[ObjectIdentifier(page)] = nil
    }

    /// Nil when no page attaches within a second.
    private func childPageID(of tabID: String) async -> String? {
        guard let attached = try? await connection.send("Target.attachToTarget", ["targetId": tabID, "flatten": true]),
              let session = attached["sessionId"] as? String else { return nil }
        let pageID: String? = await withCheckedContinuation { continuation in
            var isAnswered = false
            let answer = { (pageID: String?) in
                guard !isAnswered else { return }
                isAnswered = true
                self.connection.stopListening(in: session)
                continuation.resume(returning: pageID)
            }
            connection.listenForAttachedTargets(in: session) { targetInfo in
                if targetInfo["type"] as? String == "page" { answer(targetInfo["targetId"] as? String) }
            }
            Task {
                _ = try? await self.connection.send(
                    "Target.setAutoAttach", ["autoAttach": true, "waitForDebuggerOnStart": false, "flatten": true], in: session
                )
                try? await Task.sleep(for: .seconds(1))
                answer(nil)
            }
        }
        _ = try? await connection.send("Target.detachFromTarget", ["sessionId": session])
        return pageID
    }
}
