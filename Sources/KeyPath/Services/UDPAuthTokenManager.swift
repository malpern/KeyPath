import Foundation
import Security

/// Centralized, thread-safe manager for UDP authentication tokens
/// Provides single source of truth for token management across Keychain and shared file
@MainActor
final class UDPAuthTokenManager {
    static let shared = UDPAuthTokenManager()

    private var cachedToken: String?
    private var lastCacheUpdate: Date?

    private init() {}

    // MARK: - Token Management

    /// Ensure a token exists, generating one if needed
    func ensureToken() async throws -> String {
        if let token = await currentToken(), !token.isEmpty {
            return token
        }

        let newToken = generateSecureToken()
        try await setToken(newToken)
        return newToken
    }

    /// Get current token, preferring cache then Keychain then shared file
    func currentToken() async -> String? {
        // Use cache if recent (within 30 seconds)
        if let cached = cachedToken,
           let lastUpdate = lastCacheUpdate,
           Date().timeIntervalSince(lastUpdate) < 30 {
            return cached
        }

        // Try Keychain first (user preference)
        do {
            if let keychainToken = try KeychainService.shared.retrieveUDPToken(),
               !keychainToken.isEmpty {
                cachedToken = keychainToken
                lastCacheUpdate = Date()
                return keychainToken
            }
        } catch {
            AppLogger.shared.log("⚠️ [TokenManager] Failed to read from Keychain: \(error)")
        }

        // Fallback to shared file
        if let fileToken = readSharedToken(), !fileToken.isEmpty {
            // Sync back to Keychain if it was missing
            do {
                try KeychainService.shared.storeUDPToken(fileToken)
            } catch {
                AppLogger.shared.log("⚠️ [TokenManager] Failed to sync file token to Keychain: \(error)")
            }

            cachedToken = fileToken
            lastCacheUpdate = Date()
            return fileToken
        }

        cachedToken = nil
        return nil
    }

    /// Set token in both Keychain and shared file atomically
    func setToken(_ token: String) async throws {
        // Store in Keychain
        try KeychainService.shared.storeUDPToken(token)

        // Store in shared file atomically
        try writeSharedToken(token)

        // Update cache
        cachedToken = token
        lastCacheUpdate = Date()

        // Update non-isolated cache for thread-safe access
        await UDPAuthTokenCache.shared.updateCache(token)

        AppLogger.shared.log("🔐 [TokenManager] Token updated and synchronized")
    }

    /// Clear token from both Keychain and shared file
    func clearToken() async throws {
        // Clear from Keychain
        try KeychainService.shared.deleteUDPToken()

        // Clear from shared file
        let tokenPath = sharedTokenPath()
        do {
            try FileManager.default.removeItem(atPath: tokenPath)
        } catch CocoaError.fileNoSuchFile {
            // File doesn't exist, that's fine
        } catch {
            throw error
        }

        // Clear cache
        cachedToken = nil
        lastCacheUpdate = nil

        // Clear non-isolated cache
        await UDPAuthTokenCache.shared.updateCache(nil)

        AppLogger.shared.log("🔐 [TokenManager] Token cleared from all locations")
    }

    // MARK: - Token Generation

    /// Generate cryptographically secure token using SecRandomCopyBytes
    nonisolated func generateSecureToken(bytes: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: bytes)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes, &randomBytes)

        guard result == errSecSuccess else {
            // Fallback to SystemRandomNumberGenerator if SecRandom fails
            AppLogger.shared.log("⚠️ [TokenManager] SecRandomCopyBytes failed, using fallback")
            return generateFallbackToken(bytes: bytes)
        }

        // Convert to URL-safe Base64
        let data = Data(randomBytes)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private nonisolated func generateFallbackToken(bytes: Int) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
        return String((0 ..< bytes).map { _ in characters.randomElement()! })
    }

    // MARK: - File Operations

    /// Get cross-platform path for shared UDP auth token file
    nonisolated func sharedTokenPath() -> String {
        #if os(macOS)
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/keypath/udp-auth-token")
                .path
        #elseif os(Windows)
            let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            return supportDir?.appendingPathComponent("keypath/udp-auth-token").path ??
                NSHomeDirectory() + "/AppData/Roaming/keypath/udp-auth-token"
        #else
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/keypath/udp-auth-token")
                .path
        #endif
    }

    /// Write token to shared file with atomic operation and secure permissions
    private func writeSharedToken(_ token: String) throws {
        let tokenPath = sharedTokenPath()
        let tokenDir = (tokenPath as NSString).deletingLastPathComponent

        // Create directory with secure permissions
        try FileManager.default.createDirectory(
            atPath: tokenDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        // Write to temporary file first for atomic operation
        let tempPath = tokenPath + ".tmp"
        let tokenData = token.data(using: .utf8)!

        // Create with secure permissions from the start
        guard FileManager.default.createFile(
            atPath: tempPath,
            contents: tokenData,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw NSError(domain: "TokenManager", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create temporary token file"
            ])
        }

        // Atomic move to final location
        _ = try FileManager.default.replaceItem(
            at: URL(fileURLWithPath: tokenPath),
            withItemAt: URL(fileURLWithPath: tempPath),
            backupItemName: nil,
            options: [],
            resultingItemURL: nil
        )
    }

    /// Read token from shared file
    private func readSharedToken() -> String? {
        let tokenPath = sharedTokenPath()
        do {
            let token = try String(contentsOfFile: tokenPath, encoding: .utf8)
            return token.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}

// MARK: - Synchronous Access for Non-Isolated Contexts

/// Thread-safe cache for token access from non-MainActor contexts
actor UDPAuthTokenCache {
    private var cachedValue: String?

    static let shared = UDPAuthTokenCache()

    func value() -> String? { cachedValue }
    func updateCache(_ token: String?) { cachedValue = token }
}

// MARK: - Migration Helper

extension UDPAuthTokenManager {
    /// Migrate existing tokens from old system to new centralized system
    func migrateExistingTokens() async {
        // Check if we have a token in Keychain but not in shared file
        do {
            if let keychainToken = try KeychainService.shared.retrieveUDPToken(),
               !keychainToken.isEmpty,
               readSharedToken() == nil {
                AppLogger.shared.log("🔄 [TokenManager] Migrating existing Keychain token to shared file")
                try writeSharedToken(keychainToken)
                cachedToken = keychainToken
                lastCacheUpdate = Date()
            }
        } catch {
            AppLogger.shared.log("⚠️ [TokenManager] Migration failed: \(error)")
        }
    }
}
