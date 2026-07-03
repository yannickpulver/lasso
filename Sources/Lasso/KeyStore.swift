import Foundation
import Security

/// Stores the Gemini API key in the macOS Keychain.
public enum KeyStore {
    static var service = "com.yannickpulver.lasso"
    static let account = "gemini-api-key"

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public static func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func save(_ key: String) throws {
        delete()
        guard !key.isEmpty else { return }
        var query = baseQuery()
        query[kSecValueData as String] = Data(key.utf8)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LassoError.apiError("Couldn't save key to Keychain (error \(status)).")
        }
    }

    public static func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
