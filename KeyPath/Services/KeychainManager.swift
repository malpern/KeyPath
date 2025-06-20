import Foundation
import Security

/// Manages API key storage - using UserDefaults for development convenience
class KeychainManager {
    static let shared = KeychainManager()

    private let userDefaults = UserDefaults.standard
    private let apiKeyKey = "KeyPath.anthropic-api-key"

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

    /// Stores an API key in UserDefaults
    func setAPIKey(_ apiKey: String) throws {
        userDefaults.set(apiKey, forKey: apiKeyKey)
    }

    /// Retrieves the API key from UserDefaults
    func getAPIKey() throws -> String? {
        return userDefaults.string(forKey: apiKeyKey)
    }

    /// Deletes the API key from UserDefaults
    @discardableResult
    func deleteAPIKey() -> Bool {
        userDefaults.removeObject(forKey: apiKeyKey)
        return true
    }

    /// Updates an existing API key
    func updateAPIKey(_ apiKey: String) throws {
        try setAPIKey(apiKey)
    }

    /// Checks if an API key exists in UserDefaults
    func hasAPIKey() -> Bool {
        return userDefaults.string(forKey: apiKeyKey) != nil
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
