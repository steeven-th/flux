import Foundation
import Security

/// The translation services' keys, kept in the user's keychain rather than in Flux's database.
enum TranslationKeychain {
    private static let service = "Flux Translation"

    private static func query(for provider: TranslationProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: provider.rawValue]
    }

    /// Reading a key's attributes, unlike the key, doesn't make macOS ask for the keychain.
    static func hasKey(for provider: TranslationProvider) -> Bool {
        var query = query(for: provider)
        query[kSecReturnAttributes as String] = true
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    static func key(for provider: TranslationProvider) -> String? {
        var query = query(for: provider)
        query[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// An empty key removes it.
    static func setKey(_ key: String, for provider: TranslationProvider) {
        let query = query(for: provider)
        guard !key.isEmpty else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let data = Data(key.utf8)
        if SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
