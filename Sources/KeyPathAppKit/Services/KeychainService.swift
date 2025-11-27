import Foundation
import KeyPathCore
import Security

/// Secure storage service for sensitive data using Keychain Services
@MainActor
final class KeychainService {
    static let shared = KeychainService()

    private let serviceName = "com.keypath.app"

    private init() {}

    // MARK: - TCP Token Storage

    private let tcpTokenAccount = "tcp-auth-token"

    /// Store TCP authentication token securely in Keychain
    nonisolated func storeTCPToken(_ token: String) throws {
        let tokenData = token.data(using: .utf8) ?? Data()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: tcpTokenAccount,
            kSecValueData as String: tokenData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete existing item firs
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeyPathError.permission(.keychainSaveFailed(status: Int(status)))
        }

        AppLogger.shared.log("🔐 [Keychain] TCP token stored securely")
    }

    /// Retrieve TCP authentication token from Keychain
    nonisolated func retrieveTCPToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: tcpTokenAccount,
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

        AppLogger.shared.log("🔐 [Keychain] TCP token retrieved")
        return token
    }

    /// Delete TCP authentication token from Keychain
    nonisolated func deleteTCPToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: tcpTokenAccount
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyPathError.permission(.keychainDeleteFailed(status: Int(status)))
        }

        AppLogger.shared.log("🔐 [Keychain] TCP token deleted")
    }

    /// Check if TCP token exists in Keychain
    var hasTCPToken: Bool {
        do {
            return try retrieveTCPToken() != nil
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
