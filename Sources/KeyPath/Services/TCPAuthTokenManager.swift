import Foundation

/// Manages TCP authentication token generation and persistence
actor TCPAuthTokenManager {
    private static let tokenKey = "com.keypath.tcp.authToken"

    /// Generate a new random authentication token
    static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    /// Get or create authentication token
    static func getOrCreateToken() -> String {
        if let existing = UserDefaults.standard.string(forKey: tokenKey), !existing.isEmpty {
            return existing
        }

        let newToken = generateToken()
        UserDefaults.standard.set(newToken, forKey: tokenKey)
        return newToken
    }

    /// Clear stored token
    static func clearToken() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
    }

    /// Ensure token exists, return existing or create new
    static func ensureToken() async -> String {
        return getOrCreateToken()
    }

    /// Generate a new secure token (alias for generateToken)
    static func generateSecureToken() -> String {
        return generateToken()
    }

    /// Set a specific token
    static func setToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
    }
}
