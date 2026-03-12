import Foundation
import KeyPathCore
import KeyPathWizardCore
import Security

/// Centralized service for detecting kanata binary status across all UI components
///
/// This service provides a single source of truth for kanata binary detection,
/// ensuring consistent status reporting across the main app, wizard components,
/// and status indicators.
final class KanataBinaryDetector: Sendable {
    static let shared = KanataBinaryDetector()

    private init() {}

    // MARK: - Detection Results

    /// Result of kanata binary detection
    struct DetectionResult {
        let status: KanataBinaryStatus
        let path: String?
        let signingStatus: CodeSigningStatus?
        let isReady: Bool

        /// User-facing status message
        var statusMessage: String {
            switch status {
            case .installed:
                "Installed"
            case .bundledUnsigned:
                "Signature Issue"
            case .missing:
                "Not Found"
            case .bundledMissing:
                "CRITICAL: App Bundle Corrupted"
            }
        }

        /// Detailed description for troubleshooting
        var detailedDescription: String {
            switch status {
            case .installed:
                "Kanata binary is bundled with KeyPath and properly signed"
            case .bundledUnsigned:
                "Kanata binary found but lacks proper Developer ID signature"
            case .missing:
                "No kanata binary found in expected locations"
            case .bundledMissing:
                "CRITICAL: The kanata binary is missing from the app bundle. This indicates a packaging issue - please reinstall KeyPath from the official release."
            }
        }
    }

    /// Status of kanata binary detection
    enum KanataBinaryStatus {
        case installed // Bundled binary exists and is properly signed
        case bundledUnsigned // Available but unsigned
        case missing // Not found anywhere
        case bundledMissing // CRITICAL: Bundled binary missing from app bundle (packaging issue)
    }

    // MARK: - Detection Methods

    /// Detect current kanata binary status with unified logic
    func detectCurrentStatus() -> DetectionResult {
        AppLogger.shared.log("🔍 [KanataBinaryDetector] Starting unified kanata binary detection")

        // Priority 1: Check bundled binary (bundled + signed = installed)
        if let bundledResult = checkBundledBinary() {
            AppLogger.shared.log("📦 [KanataBinaryDetector] Bundled binary detected")
            return bundledResult
        }

        // Priority 2: Check if bundled binary is specifically missing (packaging issue)
        let bundledPath = WizardSystemPaths.bundledKanataPath
        if !Foundation.FileManager().fileExists(atPath: bundledPath) {
            AppLogger.shared.log("❌ [KanataBinaryDetector] CRITICAL: Bundled kanata binary missing from app bundle at: \(bundledPath)")
            AppLogger.shared.log("❌ [KanataBinaryDetector] This indicates a packaging issue - the app was not built correctly")
            return DetectionResult(
                status: .bundledMissing,
                path: bundledPath,
                signingStatus: nil,
                isReady: false
            )
        }

        // Priority 3: Not found anywhere (shouldn't reach here if bundled check above works)
        AppLogger.shared.log("❌ [KanataBinaryDetector] No kanata binary found")
        return DetectionResult(
            status: .missing,
            path: nil,
            signingStatus: nil,
            isReady: false
        )
    }

    /// Check if kanata needs installation (for auto-fix logic)
    /// Bundled binary present and signed = installed, no separate system install needed.
    func needsInstallation() -> Bool {
        let result = detectCurrentStatus()
        return result.status != .installed
    }

    /// Check if Kanata binary is installed and ready for use
    /// Installed == bundled binary exists and is properly signed.
    func isInstalled() -> Bool {
        let result = detectCurrentStatus()
        return result.status == .installed
    }

    /// Get recommended installation action
    func getRecommendedAction() -> ComponentRequirement? {
        let result = detectCurrentStatus()

        switch result.status {
        case .installed:
            return nil // No action needed
        case .bundledUnsigned, .missing:
            return .bundledKanataMissing // Needs reinstall or proper signature
        case .bundledMissing:
            return .bundledKanataMissing // CRITICAL: App bundle corrupted, needs reinstall
        }
    }

    /// Check if the installed kanata binary does not satisfy the expected trust identity.
    /// With bundled-only architecture, there is no separate system binary to compare against.
    func hasVersionMismatch() -> Bool {
        false
    }

    // MARK: - Private Detection Logic

    private func checkBundledBinary() -> DetectionResult? {
        let bundledPath = WizardSystemPaths.bundledKanataPath

        guard Foundation.FileManager().fileExists(atPath: bundledPath) else {
            return nil
        }

        let packageManager = PackageManager()
        let signingStatus = packageManager.getCodeSigningStatus(at: bundledPath)

        AppLogger.shared.log("🔍 [KanataBinaryDetector] Bundled binary signing: \(signingStatus)")

        if signingStatus.isDeveloperID {
            return DetectionResult(
                status: .installed,
                path: bundledPath,
                signingStatus: signingStatus,
                isReady: true
            )
        } else {
            return DetectionResult(
                status: .bundledUnsigned,
                path: bundledPath,
                signingStatus: signingStatus,
                isReady: false
            )
        }
    }

    // MARK: - Component Integration

    /// Convert detection result to ComponentRequirement array for SystemStatusChecker
    func getMissingComponents() -> [ComponentRequirement] {
        let result = detectCurrentStatus()

        switch result.status {
        case .installed:
            return [] // No missing components
        case .bundledUnsigned, .missing:
            return [.bundledKanataMissing]
        case .bundledMissing:
            return [.bundledKanataMissing] // CRITICAL: App bundle corrupted
        }
    }

    /// Convert detection result to installed components for SystemStatusChecker
    func getInstalledComponents() -> [ComponentRequirement] {
        [] // Presence is indicated by absence of missing components
    }
}
