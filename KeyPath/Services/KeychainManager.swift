import Foundation
import Security

/// Manages secure storage of API keys in the macOS Keychain
class KeychainManager {
    static let shared = KeychainManager()
    
    private let service = "com.keypath.app"
    private let account = "anthropic-api-key"
    
    private init() {}
    
    /// Errors that can occur during keychain operations
    enum KeychainError: LocalizedError {
        case unableToStore
        case unableToRetrieve
        case dataConversionError
        case itemNotFound
        case unableToDelete
        case unableToUpdate
        
        var errorDescription: String? {
            switch self {
            case .unableToStore:
                return "Unable to store API key in Keychain"
            case .unableToRetrieve:
                return "Unable to retrieve API key from Keychain"
            case .dataConversionError:
                return "Unable to convert API key data"
            case .itemNotFound:
                return "API key not found in Keychain"
            case .unableToDelete:
                return "Unable to delete API key from Keychain"
            case .unableToUpdate:
                return "Unable to update API key in Keychain"
            }
        }
    }
    
    /// Stores an API key in the keychain
    func setAPIKey(_ apiKey: String) throws {
        guard let data = apiKey.data(using: .utf8) else {
            throw KeychainError.dataConversionError
        }
        
        // Delete any existing item first
        deleteAPIKey()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.unableToStore
        }
    }
    
    /// Retrieves the API key from the keychain
    func getAPIKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let apiKey = String(data: data, encoding: .utf8) else {
                throw KeychainError.dataConversionError
            }
            return apiKey
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unableToRetrieve
        }
    }
    
    /// Deletes the API key from the keychain
    @discardableResult
    func deleteAPIKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    /// Updates an existing API key
    func updateAPIKey(_ apiKey: String) throws {
        guard let data = apiKey.data(using: .utf8) else {
            throw KeychainError.dataConversionError
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            // Item doesn't exist, create it
            try setAPIKey(apiKey)
        default:
            throw KeychainError.unableToUpdate
        }
    }
    
    /// Checks if an API key exists in the keychain
    func hasAPIKey() -> Bool {
        do {
            return try getAPIKey() != nil
        } catch {
            return false
        }
    }
    
    /// Convenience property for getting/setting the API key
    var apiKey: String? {
        get {
            try? getAPIKey()
        }
        set {
            if let newValue = newValue {
                try? setAPIKey(newValue)
            } else {
                deleteAPIKey()
            }
        }
    }
}