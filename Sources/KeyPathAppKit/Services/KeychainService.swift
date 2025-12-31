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

    // MARK: - Claude API Key Storage

    private let claudeAPIKeyAccount = "claude-api-key"

    /// Store Claude API key securely in Keychain
    /// - Parameter key: The Anthropic API key (should start with "sk-ant-")
    /// - Throws: KeyPathError if storage fails
    nonisolated func storeClaudeAPIKey(_ key: String) throws {
        assert(!key.isEmpty, "API key cannot be empty")

        let keyData = key.data(using: .utf8) ?? Data()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: claudeAPIKeyAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeyPathError.permission(.keychainSaveFailed(status: Int(status)))
        }

        AppLogger.shared.log("🔐 [Keychain] Claude API key stored securely")
    }

    /// Retrieve Claude API key from Keychain
    /// - Returns: The stored API key, or nil if not found
    nonisolated func retrieveClaudeAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: claudeAPIKeyAccount,
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
              let key = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return key
    }

    /// Delete Claude API key from Keychain
    /// - Throws: KeyPathError if deletion fails
    nonisolated func deleteClaudeAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: claudeAPIKeyAccount
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyPathError.permission(.keychainDeleteFailed(status: Int(status)))
        }

        AppLogger.shared.log("🔐 [Keychain] Claude API key deleted")
    }

    /// Check if Claude API key is available (from env var or Keychain)
    var hasClaudeAPIKey: Bool {
        getClaudeAPIKey() != nil
    }

    /// Check if Claude API key is from environment variable (developer workflow)
    var hasClaudeAPIKeyFromEnvironment: Bool {
        if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !envKey.isEmpty {
            return true
        }
        return false
    }

    /// Check if Claude API key is stored in Keychain (user workflow)
    var hasClaudeAPIKeyInKeychain: Bool {
        retrieveClaudeAPIKey() != nil
    }

    /// Get Claude API key from environment variable or Keychain
    /// Environment variable takes precedence (for developer workflow)
    /// - Returns: The API key if available from either source
    nonisolated func getClaudeAPIKey() -> String? {
        // First try environment variable (developer workflow)
        if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !envKey.isEmpty {
            return envKey
        }

        // Fall back to Keychain (user workflow)
        return retrieveClaudeAPIKey()
    }

    /// Static method to get Claude API key without needing MainActor access
    /// Use this from non-MainActor contexts
    nonisolated static func getClaudeAPIKeyStatic() -> String? {
        // First try environment variable (developer workflow)
        if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !envKey.isEmpty {
            return envKey
        }

        // Fall back to Keychain
        let serviceName = "com.keypath.app"
        let claudeAPIKeyAccount = "claude-api-key"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: claudeAPIKeyAccount,
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
              let key = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return key
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
