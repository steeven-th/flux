import Foundation

/// The browser-wide DevTools protocol, for what a page's own connection can't reach: tab targets
/// and extensions' service workers.
@MainActor
final class DevToolsConnection {
    static let browser = DevToolsConnection()

    struct ProtocolError: Error {
        let message: String
    }

    /// Replies are plain JSON values, delivered on the main thread.
    private struct Payload: @unchecked Sendable {
        let json: [String: Any]
    }

    /// By session: called with each target that attaches under it.
    private var attachListeners: [String: ([String: Any]) -> Void] = [:]

    private init() {
        FLXDevTools.eventHandler = { [weak self] method, params, sessionID in
            MainActor.assumeIsolated { self?.receive(method, params, in: sessionID) }
        }
    }

    var isAvailable: Bool {
        FLXDevTools.isAvailable
    }

    func send(_ method: String, _ params: [String: Any] = [:], in session: String? = nil) async throws -> [String: Any] {
        let payload: Payload = try await withCheckedThrowingContinuation { continuation in
            FLXDevTools.sendMethod(method, params: params, sessionID: session) { result, error in
                if let result {
                    continuation.resume(returning: Payload(json: result))
                } else {
                    continuation.resume(throwing: ProtocolError(message: error ?? method))
                }
            }
        }
        return payload.json
    }

    func listenForAttachedTargets(in session: String, _ listener: @escaping ([String: Any]) -> Void) {
        attachListeners[session] = listener
    }

    func stopListening(in session: String) {
        attachListeners[session] = nil
    }

    private func receive(_ method: String, _ params: [String: Any], in session: String?) {
        guard method == "Target.attachedToTarget", let session,
              let targetInfo = params["targetInfo"] as? [String: Any] else { return }
        attachListeners[session]?(targetInfo)
    }
}
