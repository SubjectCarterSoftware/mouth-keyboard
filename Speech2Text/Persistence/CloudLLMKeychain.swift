import Foundation
import Security

enum CloudLLMKeychain {
    private static let servicePrefix = "com.elicarter.Speech2Text.cloudLLM"

    static func saveAPIKey(_ key: String, for provider: CloudLLMProvider) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }

        let service = serviceName(for: provider)

        // Delete any existing item first.
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        guard !key.isEmpty else {
            // Caller passed an empty string — treat as deletion.
            return true
        }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func loadAPIKey(for provider: CloudLLMProvider) -> String? {
        let service = serviceName(for: provider)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteAPIKey(for provider: CloudLLMProvider) {
        let service = serviceName(for: provider)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]

        SecItemDelete(query as CFDictionary)
    }

    private static func serviceName(for provider: CloudLLMProvider) -> String {
        "\(servicePrefix).\(provider.rawValue)"
    }
}
