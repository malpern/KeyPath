import CryptoKit
import Foundation
import KeyPathCore
import Security

/// Handles encryption/decryption of activity logs using AES-GCM
/// Key is stored in Keychain, bound to this device only
public actor ActivityLogEncryption {
    // MARK: - Constants

    private static let keychainService = "com.keypath.activitylog"
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

    // MARK: - Key Management

    /// Get or create the encryption key
    /// Creates a new key on first call, returns existing key thereafter
    public func getOrCreateKey() throws -> SymmetricKey {
        // Try to read existing key
        if let existingKey = try? readKeyFromKeychain() {
            return existingKey
        }

        // Generate new key
        let newKey = SymmetricKey(size: .bits256)
        try storeKeyInKeychain(newKey)
        AppLogger.shared.log("🔐 [ActivityLogEncryption] Generated new encryption key")
        return newKey
    }

    /// Check if an encryption key exists
    public func keyExists() -> Bool {
        (try? readKeyFromKeychain()) != nil
    }

    /// Delete the encryption key (used when resetting activity logging)
    public func deleteKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            throw EncryptionError.keychainDeleteFailed(status)
        }
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

        // Delete any existing key first
        try? deleteKey()

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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
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
