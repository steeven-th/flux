import CommonCrypto
import Foundation
import Security

/// How Chromium protects passwords and cookies on macOS: AES-128-CBC with a key derived from a
/// secret it keeps in the keychain as "<browser> Safe Storage". Protected values start with "v10".
struct ChromiumSafeStorage {
    private static let prefix = Data("v10".utf8)
    /// Chromium uses a fixed one.
    private static let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)

    private let key: Data

    init(secret: String) {
        var key = Data(count: kCCKeySizeAES128)
        let salt = Array("saltysalt".utf8)
        key.withUnsafeMutableBytes { buffer in
            _ = CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2), secret, secret.utf8.count, salt, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                buffer.bindMemory(to: UInt8.self).baseAddress, kCCKeySizeAES128
            )
        }
        self.key = key
    }

    /// Arc's, which macOS lets Flux read once the user enters their password.
    static func arc() -> ChromiumSafeStorage? {
        secret(service: "Arc Safe Storage", account: "Arc").map(ChromiumSafeStorage.init(secret:))
    }

    /// Flux's own, which Chromium makes the first time it needs it: when an import comes first,
    /// it is made here, the way Chromium makes it.
    static func flux() -> ChromiumSafeStorage? {
        let service = "Chromium Safe Storage", account = "Chromium"
        if let secret = secret(service: service, account: account) { return ChromiumSafeStorage(secret: secret) }
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let secret = Data(bytes).base64EncodedString()
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecValueData as String: Data(secret.utf8),
        ]
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { return nil }
        return ChromiumSafeStorage(secret: secret)
    }

    private static func secret(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Nil when the value isn't protected this way, or with another key.
    func decrypt(_ value: Data) -> Data? {
        guard value.starts(with: Self.prefix) else { return nil }
        // CommonCrypto would remove the padding without checking it, so a wrong key would pass
        // now and then with garbage.
        guard let plain = crypt(CCOperation(kCCDecrypt), value.dropFirst(Self.prefix.count)),
              let padding = plain.last, (1...kCCBlockSizeAES128).contains(Int(padding)), plain.count >= Int(padding),
              plain.suffix(Int(padding)).allSatisfy({ $0 == padding }) else { return nil }
        return plain.dropLast(Int(padding))
    }

    func encrypt(_ value: Data) -> Data {
        let padding = kCCBlockSizeAES128 - value.count % kCCBlockSizeAES128
        let padded = value + Data(repeating: UInt8(padding), count: padding)
        return Self.prefix + (crypt(CCOperation(kCCEncrypt), padded) ?? Data())
    }

    /// Without padding: it is added and checked above.
    private func crypt(_ operation: CCOperation, _ input: Data) -> Data? {
        var output = Data(count: input.count)
        var length = 0
        let status = output.withUnsafeMutableBytes { out in
            input.withUnsafeBytes { inBytes in
                key.withUnsafeBytes { keyBytes in
                    Self.iv.withUnsafeBytes { ivBytes in
                        CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), 0,
                                keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                                inBytes.baseAddress, input.count, out.baseAddress, input.count, &length)
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return output.prefix(length)
    }
}
