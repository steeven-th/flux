import AppKit
import Observation
import Security

/// The user's GitHub account, for live folders of pull requests and issues. Signing in uses
/// GitHub's device flow, made for apps without a web server: GitHub shows a page where the user
/// types a code Flux shows, and Flux waits for the answer.
@MainActor
@Observable
final class GitHubAccount {
    static let shared = GitHubAccount()

    /// Flux's OAuth app on GitHub, with its device flow on. Public, as for every desktop app.
    static let clientID = "Ov23li9RxcDF7fwsbAbP"

    struct DeviceCode {
        let userCode: String
        let verificationURL: URL
    }

    private(set) var isSignedIn = Keychain.hasToken
    private(set) var login: String?
    /// While signing in, the code to type on GitHub's page.
    private(set) var deviceCode: DeviceCode?
    private(set) var signInError: String?
    @ObservationIgnored private var signInTask: Task<Void, Never>?

    var isAvailable: Bool { !Self.clientID.isEmpty }

    func signIn() {
        signInTask?.cancel()
        signInError = nil
        signInTask = Task {
            do {
                let token = try await requestToken()
                Keychain.setToken(token)
                isSignedIn = true
                login = try? await fetchLogin(token: token)
            } catch is CancellationError {
            } catch {
                signInError = error.localizedDescription
            }
            deviceCode = nil
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
        deviceCode = nil
    }

    func signOut() {
        Keychain.setToken(nil)
        isSignedIn = false
        login = nil
    }

    /// The newest issues and pull requests matching a search. Open ones only unless the search
    /// says otherwise, as on github.com/pulls.
    func search(_ query: String) async throws -> [LiveItem] {
        guard let token = Keychain.token else { throw LiveFolderError.notSignedIn }
        if login == nil { login = try await fetchLogin(token: token) }
        var query = query
        if query.range(of: #"\b(is:(open|closed|merged|unmerged)|state:)"#, options: .regularExpression) == nil {
            query += " is:open"
        }
        var components = URLComponents(string: "https://api.github.com/search/issues")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query.replacingOccurrences(of: "@me", with: login ?? "@me")),
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "per_page", value: String(LiveSource.maxItems)),
        ]
        let data = try await get(components.url!, token: token)
        struct Results: Decodable {
            struct Item: Decodable {
                let title: String
                let html_url: String
            }
            let items: [Item]
        }
        return try JSONDecoder().decode(Results.self, from: data).items.map {
            LiveItem(id: $0.html_url, title: $0.title, url: $0.html_url)
        }
    }

    private func fetchLogin(token: String) async throws -> String {
        struct User: Decodable { let login: String }
        return try JSONDecoder().decode(User.self, from: try await get(URL(string: "https://api.github.com/user")!, token: token)).login
    }

    private func get(_ url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            signOut()
            throw LiveFolderError.notSignedIn
        }
        return data
    }

    // Device flow: https://docs.github.com/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow

    private func requestToken() async throws -> String {
        struct Code: Decodable {
            let device_code: String
            let user_code: String
            let verification_uri: String
            let interval: Int
            let expires_in: Int
        }
        // Private repositories need the repo scope: OAuth apps have no read-only one.
        let code = try JSONDecoder().decode(Code.self, from: try await post(
            "https://github.com/login/device/code", ["client_id": Self.clientID, "scope": "repo"]
        ))
        guard let url = URL(string: code.verification_uri) else { throw URLError(.badURL) }
        deviceCode = DeviceCode(userCode: code.user_code, verificationURL: url)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code.user_code, forType: .string)
        NSWorkspace.shared.open(url)

        struct Answer: Decodable {
            let access_token: String?
            let error: String?
            let interval: Int?
        }
        var interval = code.interval
        let deadline = Date().addingTimeInterval(TimeInterval(code.expires_in))
        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval))
            let answer = try JSONDecoder().decode(Answer.self, from: try await post(
                "https://github.com/login/oauth/access_token",
                ["client_id": Self.clientID, "device_code": code.device_code, "grant_type": "urn:ietf:params:oauth:grant-type:device_code"]
            ))
            if let token = answer.access_token { return token }
            switch answer.error {
            case "authorization_pending": continue
            case "slow_down": interval = answer.interval ?? interval + 5
            default: throw URLError(.userCancelledAuthentication)
            }
        }
        throw URLError(.timedOut)
    }

    private func post(_ address: String, _ fields: [String: String]) async throws -> Data {
        var request = URLRequest(url: URL(string: address)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var body = URLComponents()
        body.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((body.percentEncodedQuery ?? "").utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        return try await URLSession.shared.data(for: request).0
    }

    /// The token, in the user's keychain rather than in Flux's database.
    private enum Keychain {
        private static var query: [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "Flux GitHub",
                kSecAttrAccount as String: "token",
            ]
        }

        static var hasToken: Bool {
            var query = query
            query[kSecReturnAttributes as String] = true
            var result: AnyObject?
            return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
        }

        static var token: String? {
            var query = query
            query[kSecReturnData as String] = true
            var result: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }

        static func setToken(_ token: String?) {
            SecItemDelete(query as CFDictionary)
            guard let token else { return }
            var item = query
            item[kSecValueData as String] = Data(token.utf8)
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
