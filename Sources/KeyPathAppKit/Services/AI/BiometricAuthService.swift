import Foundation
import KeyPathCore
import LocalAuthentication

/// Service for biometric authentication before expensive API operations
/// Provides Touch ID/Face ID authentication with password fallback
@MainActor
public class BiometricAuthService {
    /// Shared instance
    public static let shared = BiometricAuthService()

    /// UserDefaults key for biometric auth preference
    public static let requireBiometricAuthKey = "KeyPath.AI.RequireBiometricAuth"

    /// Whether user has authenticated this session (persists until app restart)
    private var hasAuthenticatedThisSession: Bool = false

    private init() {}

    /// Authentication result
    public enum AuthResult: Sendable {
        case authenticated
        case cancelled
        case failed(String) // Store error message instead of Error for Sendable
        case notRequired
    }

    /// Check if biometric authentication is available on this device
    public func isBiometricAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// Get the type of biometric authentication available
    public func biometricType() -> LABiometryType {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return context.biometryType
    }

    /// Human-readable name for the biometric type
    public var biometricTypeName: String {
        switch biometricType() {
        case .touchID:
            return "Touch ID"
        case .faceID:
            return "Face ID"
        case .opticID:
            return "Optic ID"
        case .none:
            return "Password"
        @unknown default:
            return "Biometric"
        }
    }

    /// Check if user has enabled biometric auth requirement in settings
    public var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.requireBiometricAuthKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.requireBiometricAuthKey) }
    }

    /// Authenticate user before an expensive operation
    /// - Parameter reason: Explanation shown to user (should mention cost)
    /// - Returns: AuthResult indicating the outcome
    public func authenticate(
        reason: String = "This AI generation will use your Anthropic API quota and cost approximately $0.01-0.03. Authenticate to proceed?"
    ) async -> AuthResult {
        // Check if auth is required
        guard isEnabled else {
            AppLogger.shared.log("🔓 [BiometricAuth] Auth not required (disabled in settings)")
            return .notRequired
        }

        // Check if already authenticated this session
        if hasAuthenticatedThisSession {
            AppLogger.shared.log("🔓 [BiometricAuth] Already authenticated this session")
            return .authenticated
        }

        AppLogger.shared.log("🔐 [BiometricAuth] Requesting authentication...")

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        // Check availability
        var error: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication // Fallback to password

        do {
            let success = try await context.evaluatePolicy(policy, localizedReason: reason)

            if success {
                hasAuthenticatedThisSession = true
                AppLogger.shared.log("✅ [BiometricAuth] Authentication successful (valid for session)")
                return .authenticated
            } else {
                AppLogger.shared.log("❌ [BiometricAuth] Authentication failed")
                return .cancelled
            }
        } catch let authError as LAError {
            switch authError.code {
            case .userCancel, .appCancel:
                AppLogger.shared.log("🚫 [BiometricAuth] User cancelled authentication")
                return .cancelled
            case .userFallback:
                // User wants to use password - try password auth
                return await authenticateWithPassword(reason: reason)
            case .biometryNotAvailable, .biometryNotEnrolled:
                // No biometrics - try password
                return await authenticateWithPassword(reason: reason)
            case .biometryLockout:
                AppLogger.shared.log("🔒 [BiometricAuth] Biometry locked out")
                return await authenticateWithPassword(reason: reason)
            default:
                AppLogger.shared.log("❌ [BiometricAuth] Error: \(authError.localizedDescription)")
                return .failed(authError.localizedDescription)
            }
        } catch {
            AppLogger.shared.log("❌ [BiometricAuth] Unexpected error: \(error)")
            return .failed(error.localizedDescription)
        }
    }

    /// Fallback to password authentication
    private func authenticateWithPassword(reason: String) async -> AuthResult {
        let context = LAContext()

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No authentication available - allow operation (user can disable in settings)
            AppLogger.shared.log("⚠️ [BiometricAuth] No auth available - allowing operation")
            return .authenticated
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )

            if success {
                hasAuthenticatedThisSession = true
                AppLogger.shared.log("✅ [BiometricAuth] Password authentication successful (valid for session)")
                return .authenticated
            } else {
                return .cancelled
            }
        } catch {
            AppLogger.shared.log("❌ [BiometricAuth] Password auth error: \(error)")
            return .failed(error.localizedDescription)
        }
    }

    /// Clear authentication for this session (force re-auth on next call)
    public func clearAuthCache() {
        hasAuthenticatedThisSession = false
        AppLogger.shared.log("🔐 [BiometricAuth] Session auth cleared")
    }

    /// Check if authentication would be required for next API call
    public var wouldRequireAuth: Bool {
        guard isEnabled else { return false }
        return !hasAuthenticatedThisSession
    }
}
