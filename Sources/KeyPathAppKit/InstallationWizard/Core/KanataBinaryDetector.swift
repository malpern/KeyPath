import Foundation
import KeyPathCore
import KeyPathWizardCore

/// Centralized service for detecting kanata binary status across all UI components
///
/// This service provides a single source of truth for kanata binary detection,
/// ensuring consistent status reporting across the main app, wizard components,
/// and status indicators.
@MainActor
final class KanataBinaryDetector {
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
            case .systemInstalled:
                "System Installation Ready"
            case .bundledAvailable:
                "Ready to Install"
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
            case .systemInstalled:
                "Kanata is properly installed at system location and ready for LaunchDaemon use"
            case .bundledAvailable:
                "Kanata binary is bundled with the app and ready to be installed to the system location for stable permissions"
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
        case systemInstalled // Properly installed at /Library/KeyPath/bin/kanata
        case bundledAvailable // Available in app bundle, can be installed
        case bundledUnsigned // Available but unsigned
        case missing // Not found anywhere
        case bundledMissing // CRITICAL: Bundled binary missing from app bundle (packaging issue)
    }

    // MARK: - Detection Methods

    /// Detect current kanata binary status with unified logic
    func detectCurrentStatus() -> DetectionResult {
        AppLogger.shared.log("🔍 [KanataBinaryDetector] Starting unified kanata binary detection")

        // Priority 1: Check system installation path
        if let systemResult = checkSystemInstallation() {
            AppLogger.shared.log("✅ [KanataBinaryDetector] System installation detected")
            return systemResult
        }

        // Priority 2: Check bundled binary
        if let bundledResult = checkBundledBinary() {
            AppLogger.shared.log("📦 [KanataBinaryDetector] Bundled binary detected")
            return bundledResult
        }

        // Priority 3: Check if bundled binary is specifically missing (packaging issue)
        let bundledPath = WizardSystemPaths.bundledKanataPath
        if !FileManager.default.fileExists(atPath: bundledPath) {
            AppLogger.shared.log("❌ [KanataBinaryDetector] CRITICAL: Bundled kanata binary missing from app bundle at: \(bundledPath)")
            AppLogger.shared.log("❌ [KanataBinaryDetector] This indicates a packaging issue - the app was not built correctly")
            return DetectionResult(
                status: .bundledMissing,
                path: bundledPath,
                signingStatus: nil,
                isReady: false
            )
        }

        // Priority 4: Not found anywhere (shouldn't reach here if bundled check above works)
        AppLogger.shared.log("❌ [KanataBinaryDetector] No kanata binary found")
        return DetectionResult(
            status: .missing,
            path: nil,
            signingStatus: nil,
            isReady: false
        )
    }

    /// Check if kanata needs installation (for auto-fix logic)
    /// With KeyPath’s permission model, the system-installed kanata path is the canonical identity.
    /// The bundled binary is installer payload; users should grant permissions to /Library/KeyPath/bin/kanata.
    func needsInstallation() -> Bool {
        let result = detectCurrentStatus()
        // Anything other than a valid system installation should be treated as needing install.
        return result.status != .systemInstalled
    }

    /// Check if Kanata binary is installed and ready for use
    /// Installed == present at the canonical system location.
    func isInstalled() -> Bool {
        let result = detectCurrentStatus()
        return result.status == .systemInstalled
    }

    /// Get recommended installation action
    /// Bundled Kanata is not sufficient for canonical TCC identity; we still want the system install.
    func getRecommendedAction() -> ComponentRequirement? {
        let result = detectCurrentStatus()

        switch result.status {
        case .systemInstalled:
            return nil // No action needed
        case .bundledAvailable:
            return .kanataBinaryMissing // Needs installation to system path
        case .bundledUnsigned:
            return .kanataBinaryMissing // Needs proper signature
        case .missing:
            return .kanataBinaryMissing // Needs installation
        case .bundledMissing:
            return .bundledKanataMissing // CRITICAL: App bundle corrupted, needs reinstall
        }
    }

    // MARK: - Private Detection Logic

    private func checkSystemInstallation() -> DetectionResult? {
        let systemPath = WizardSystemPaths.kanataSystemInstallPath

        guard FileManager.default.fileExists(atPath: systemPath) else {
            return nil
        }

        let packageManager = PackageManager()
        let signingStatus = packageManager.getCodeSigningStatus(at: systemPath)
        let isReady = signingStatus.isDeveloperID

        AppLogger.shared.log("🔍 [KanataBinaryDetector] System binary signing: \(signingStatus)")

        return DetectionResult(
            status: .systemInstalled,
            path: systemPath,
            signingStatus: signingStatus,
            isReady: isReady
        )
    }

    private func checkBundledBinary() -> DetectionResult? {
        let bundledPath = WizardSystemPaths.bundledKanataPath

        guard FileManager.default.fileExists(atPath: bundledPath) else {
            return nil
        }

        let packageManager = PackageManager()
        let signingStatus = packageManager.getCodeSigningStatus(at: bundledPath)

        AppLogger.shared.log("🔍 [KanataBinaryDetector] Bundled binary signing: \(signingStatus)")

        if signingStatus.isDeveloperID {
            return DetectionResult(
                status: .bundledAvailable,
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
    /// With canonical path architecture, only system-installed kanata counts as installed.
    func getMissingComponents() -> [ComponentRequirement] {
        let result = detectCurrentStatus()

        switch result.status {
        case .systemInstalled:
            return [] // No missing components
        case .bundledAvailable, .bundledUnsigned, .missing:
            return [.kanataBinaryMissing]
        case .bundledMissing:
            return [.bundledKanataMissing] // CRITICAL: App bundle corrupted
        }
    }

    /// Convert detection result to installed components for SystemStatusChecker
    func getInstalledComponents() -> [ComponentRequirement] {
        let result = detectCurrentStatus()

        switch result.status {
        case .systemInstalled:
            return [] // Use the absence of .kanataBinaryMissing to indicate "installed"
        case .bundledAvailable, .bundledUnsigned, .missing, .bundledMissing:
            return []
        }
    }
}
