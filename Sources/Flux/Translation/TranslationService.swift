import Foundation

/// The services pages can be translated with, each with the user's own key. Chromium's own
/// translation needs Google keys only Chrome and its partners have.
enum TranslationProvider: String, CaseIterable, Identifiable {
    case deepL, google

    var id: Self { self }

    var name: String {
        switch self {
        case .deepL: "DeepL"
        case .google: "Google Cloud Translation"
        }
    }

    /// Where the user gets a key.
    var keyPage: URL {
        switch self {
        case .deepL: URL(string: "https://www.deepl.com/pro-api")!
        case .google: URL(string: "https://console.cloud.google.com/apis/library/translate.googleapis.com")!
        }
    }

    /// The free characters per month, or nil when the service tells it.
    var freeCharacters: Int? {
        switch self {
        case .deepL: nil
        case .google: 500_000
        }
    }

    func service(key: String) -> TranslationService {
        switch self {
        case .deepL: DeepLService(key: key)
        case .google: GoogleTranslationService(key: key)
        }
    }
}

protocol TranslationService: Sendable {
    /// The most texts one request takes.
    var batchSize: Int { get }
    /// The translations, in the order of `texts`.
    func translate(_ texts: [String], into language: Locale.Language) async throws -> [String]
    /// Characters used this period, and the limit, when the service tells them.
    func usage() async throws -> (used: Int, limit: Int)?
}

enum TranslationError: LocalizedError {
    case keyRefused, quotaReached, failed(Int)

    var errorDescription: String? {
        switch self {
        case .keyRefused: String(localized: "The translation key was refused")
        case .quotaReached: String(localized: "The translation quota for this month is reached")
        case .failed(let status): String(localized: "Translation failed (error \(status))")
        }
    }
}

private func send(_ request: URLRequest) async throws -> Data {
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    switch status {
    case 200..<300: return data
    case 401, 403: throw TranslationError.keyRefused
    // 456 is DeepL's, 429 both services' when requests come too fast or the quota is spent.
    case 429, 456: throw TranslationError.quotaReached
    default: throw TranslationError.failed(status)
    }
}

struct DeepLService: TranslationService {
    let key: String
    let batchSize = 50

    /// Free keys end in ":fx" and have a server of their own.
    private var server: URL {
        URL(string: key.hasSuffix(":fx") ? "https://api-free.deepl.com/v2/" : "https://api.deepl.com/v2/")!
    }

    private func request(_ path: String) -> URLRequest {
        var request = URLRequest(url: server.appending(path: path))
        request.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
        return request
    }

    func translate(_ texts: [String], into language: Locale.Language) async throws -> [String] {
        var request = request("translate")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": texts, "target_lang": Self.code(for: language)])
        struct Response: Decodable {
            struct Translation: Decodable { let text: String }
            let translations: [Translation]
        }
        return try JSONDecoder().decode(Response.self, from: try await send(request)).translations.map(\.text)
    }

    func usage() async throws -> (used: Int, limit: Int)? {
        struct Response: Decodable {
            let character_count: Int
            let character_limit: Int
        }
        let response = try JSONDecoder().decode(Response.self, from: try await send(request("usage")))
        return (response.character_count, response.character_limit)
    }

    /// DeepL wants a variant for English and Portuguese.
    private static func code(for language: Locale.Language) -> String {
        let code = (language.languageCode?.identifier ?? "en").uppercased()
        let region = language.region?.identifier
        switch code {
        case "EN": return region == "GB" ? "EN-GB" : "EN-US"
        case "PT": return region == "BR" ? "PT-BR" : "PT-PT"
        default: return code
        }
    }
}

struct GoogleTranslationService: TranslationService {
    let key: String
    let batchSize = 100

    func translate(_ texts: [String], into language: Locale.Language) async throws -> [String] {
        var components = URLComponents(string: "https://translation.googleapis.com/language/translate/v2")!
        components.queryItems = [URLQueryItem(name: "key", value: key)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "q": texts, "target": language.languageCode?.identifier ?? "en", "format": "text",
        ])
        struct Response: Decodable {
            struct Body: Decodable {
                struct Translation: Decodable { let translatedText: String }
                let translations: [Translation]
            }
            let data: Body
        }
        do {
            return try JSONDecoder().decode(Response.self, from: try await send(request)).data.translations.map(\.translatedText)
        } catch TranslationError.failed(400) {
            // Google answers a bad key with a plain 400.
            throw TranslationError.keyRefused
        }
    }

    /// Google doesn't tell: Flux counts what it sends.
    func usage() async throws -> (used: Int, limit: Int)? {
        nil
    }
}
