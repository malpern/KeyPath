import Foundation
import Security

/// Secure storage service for sensitive data using Keychain Services
@MainActor
final class KeychainService {
    static let shared = KeychainService()

    private let serviceName = "com.keypath.app"

    private init() {}

    // MARK: - UDP Token Storage

    private let udpTokenAccount = "udp-auth-token"

    /// Store UDP authentication token securely in Keychain
    nonisolated func storeUDPToken(_ token: String) throws {
        let tokenData = token.data(using: .utf8) ?? Data()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: udpTokenAccount,
            kSecValueData as String: tokenData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeyPathError.permission(.keychainSaveFailed(status: Int(status)))
        }

        AppLogger.shared.log("🔐 [Keychain] UDP token stored securely")
    }

    /// Retrieve UDP authentication token from Keychain
    nonisolated func retrieveUDPToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: udpTokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8)
        else {
            throw KeyPathError.permission(.keychainLoadFailed(status: Int(status)))
        }

        AppLogger.shared.log("🔐 [Keychain] UDP token retrieved")
        return token
    }

    /// Delete UDP authentication token from Keychain
    nonisolated func deleteUDPToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: udpTokenAccount
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyPathError.permission(.keychainDeleteFailed(status: Int(status)))
        }

        AppLogger.shared.log("🔐 [Keychain] UDP token deleted")
    }

    /// Check if UDP token exists in Keychain
    var hasUDPToken: Bool {
        do {
            return try retrieveUDPToken() != nil
        } catch {
            return false
        }
    }

    // MARK: - Session Storage (Optional)

    /// Store session information temporarily (expires with app restart)
    private var sessionCache: [String: Date] = [:]

    func cacheSessionExpiry(sessionId: String, expiryDate: Date) {
        sessionCache[sessionId] = expiryDate
    }

    func getSessionExpiry(sessionId: String) -> Date? {
        sessionCache[sessionId]
    }

    func clearSessionCache() {
        sessionCache.removeAll()
        AppLogger.shared.log("🔐 [Keychain] Session cache cleared")
    }
}

// MARK: - Error Types
// (Removed deprecated KeychainError - now using KeyPathError directly)
