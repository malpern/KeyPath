import CryptoKit
import Foundation
import KeyPathCore
import LocalAuthentication
import Security

/// Handles encryption/decryption of activity logs using AES-GCM
/// Key is stored in Keychain, bound to this device only
public actor ActivityLogEncryption {
    // MARK: - Constants

    /// Unit tests use a separate Keychain service so a test calling
    /// `deleteKey()` (e.g. via `ActivityLogStorage.clearAll()`) can never
    /// delete the production key and orphan real encrypted logs.
    static let keychainService = TestEnvironment.isRunningTests
        ? "com.keypath.activitylog.tests"
        : "com.keypath.activitylog"
    private static let keychainAccount = "encryption-key"

    // MARK: - Errors

    public enum EncryptionError: Error, LocalizedError {
        case keyGenerationFailed
        case keychainWriteFailed(OSStatus)
        case keychainReadFailed(OSStatus)
        case keychainDeleteFailed(OSStatus)
        case encryptionFailed(Error)
        case decryptionFailed(Error)
        case invalidData

        public var errorDescription: String? {
            switch self {
            case .keyGenerationFailed:
                "Failed to generate encryption key"
            case let .keychainWriteFailed(status):
                "Failed to store key in Keychain (status: \(status))"
            case let .keychainReadFailed(status):
                "Failed to read key from Keychain (status: \(status))"
            case let .keychainDeleteFailed(status):
                "Failed to delete key from Keychain (status: \(status))"
            case let .encryptionFailed(error):
                "Encryption failed: \(error.localizedDescription)"
            case let .decryptionFailed(error):
                "Decryption failed: \(error.localizedDescription)"
            case .invalidData:
                "Invalid encrypted data format"
            }
        }
    }

    // MARK: - Singleton

    public static let shared = ActivityLogEncryption()

    private init() {}

    private var cachedKey: SymmetricKey?
    private var userOpenedActivityHistory = false

    /// Called only by an explicit activity-history UI action, never plugin startup.
    public func authorizeActivityHistoryAccess() {
        userOpenedActivityHistory = true
    }

    private func requireUserAction() throws {
        guard userOpenedActivityHistory || TestEnvironment.isRunningTests else {
            throw EncryptionError.keychainReadFailed(errSecInteractionNotAllowed)
        }
    }

    // MARK: - Key Management

    /// Get or create the encryption key
    /// Creates a new key on first call, returns existing key thereafter
    public func getOrCreateKey() throws -> SymmetricKey {
        if let cachedKey { return cachedKey }
        try requireUserAction()
        do {
            let key = try readKeyFromKeychain()
            cachedKey = key
            return key
        } catch let EncryptionError.keychainReadFailed(status) where status == errSecItemNotFound {
            // Only absence permits creation. Denied or locked reads must preserve
            // the existing key and the logs encrypted with it.
            let key = SymmetricKey(size: .bits256)
            try storeKeyInKeychain(key)
            cachedKey = key
            AppLogger.shared.log("🔐 [ActivityLogEncryption] Generated new encryption key")
            return key
        }
    }

    /// Check if an encryption key exists
    public func keyExists() -> Bool {
        if cachedKey != nil { return true }
        guard userOpenedActivityHistory || TestEnvironment.isRunningTests else { return false }
        guard let key = try? readKeyFromKeychain() else { return false }
        cachedKey = key
        return true
    }

    /// Delete the encryption key (used when resetting activity logging)
    public func deleteKey() throws {
        try requireUserAction()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            throw EncryptionError.keychainDeleteFailed(status)
        }
        cachedKey = nil
        AppLogger.shared.log("🔐 [ActivityLogEncryption] Deleted encryption key")
    }

    // MARK: - Encryption/Decryption

    /// Encrypt data using AES-GCM
    public func encrypt(_ data: Data) throws -> Data {
        let key = try getOrCreateKey()

        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            guard let combined = sealedBox.combined else {
                throw EncryptionError.invalidData
            }
            return combined
        } catch let error as EncryptionError {
            throw error
        } catch {
            throw EncryptionError.encryptionFailed(error)
        }
    }

    /// Decrypt data using AES-GCM
    public func decrypt(_ data: Data) throws -> Data {
        let key = try getOrCreateKey()

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch let error as EncryptionError {
            throw error
        } catch {
            throw EncryptionError.decryptionFailed(error)
        }
    }

    // MARK: - Private Keychain Helpers

    private func storeKeyInKeychain(_ key: SymmetricKey) throws {
        // Convert key to Data
        let keyData = key.withUnsafeBytes { Data($0) }

        // Store new key with device-only access
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            throw EncryptionError.keychainWriteFailed(status)
        }
    }

    private func readKeyFromKeychain() throws -> SymmetricKey {
        // Activity logging runs in the background; it must never interrupt
        // setup with Keychain authorization dialogs.
        let context = LAContext()
        context.interactionNotAllowed = !userOpenedActivityHistory
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecUseAuthenticationContext as String: context,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let keyData = result as? Data else {
            throw EncryptionError.keychainReadFailed(status)
        }

        return SymmetricKey(data: keyData)
    }
}
