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

    /// Check if the installed kanata binary does not satisfy the expected trust identity.
    ///
    /// This intentionally avoids byte-for-byte comparisons so routine app upgrades
    /// (same signer/team identity) do not force unnecessary reinstalls.
    func hasVersionMismatch() -> Bool {
        let systemPath = WizardSystemPaths.kanataSystemInstallPath
        let bundledPath = WizardSystemPaths.bundledKanataPath
        let fm = Foundation.FileManager()

        let sysExists = fm.fileExists(atPath: systemPath)
        let bunExists = fm.fileExists(atPath: bundledPath)

        AppLogger.shared.log("🔍 [KanataBinaryDetector] hasVersionMismatch: system=\(systemPath) exists=\(sysExists), bundled=\(bundledPath) exists=\(bunExists)")

        guard sysExists, bunExists else {
            return false // Can't compare if one is missing
        }

        switch evaluateTrust(systemPath: systemPath, bundledPath: bundledPath) {
        case .trusted:
            AppLogger.shared.log("🔍 [KanataBinaryDetector] hasVersionMismatch: trust check passed → false")
            return false
        case let .untrusted(reason):
            AppLogger.shared.log("🔍 [KanataBinaryDetector] hasVersionMismatch: untrusted (\(reason)) → true")
            return true
        case let .unknown(reason):
            // Prefer avoiding false-positive reinstall loops when trust cannot be determined.
            AppLogger.shared.log("⚠️ [KanataBinaryDetector] hasVersionMismatch: unknown trust (\(reason)) → false")
            return false
        }
    }

    // MARK: - Private Detection Logic

    private func checkSystemInstallation() -> DetectionResult? {
        let systemPath = WizardSystemPaths.kanataSystemInstallPath

        guard Foundation.FileManager().fileExists(atPath: systemPath) else {
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

        guard Foundation.FileManager().fileExists(atPath: bundledPath) else {
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

    // MARK: - Trust Evaluation

    private enum TrustResult {
        case trusted
        case untrusted(reason: String)
        case unknown(reason: String)
    }

    private struct SigningIdentity {
        let identifier: String?
        let teamIdentifier: String?
    }

    private func evaluateTrust(systemPath: String, bundledPath: String) -> TrustResult {
        let packageManager = PackageManager()
        let systemSigning = packageManager.getCodeSigningStatus(at: systemPath)
        let bundledSigning = packageManager.getCodeSigningStatus(at: bundledPath)

        guard systemSigning.isDeveloperID else {
            return .untrusted(reason: "reason_code=system_not_developer_id")
        }
        guard bundledSigning.isDeveloperID else {
            return .untrusted(reason: "reason_code=bundled_not_developer_id")
        }

        let systemIdentity = signingIdentity(forPath: systemPath)
        let bundledIdentity = signingIdentity(forPath: bundledPath)

        guard let systemIdentity, let bundledIdentity else {
            return .unknown(reason: "reason_code=identity_unreadable")
        }

        if let systemTeam = systemIdentity.teamIdentifier,
           let bundledTeam = bundledIdentity.teamIdentifier,
           systemTeam != bundledTeam
        {
            return .untrusted(reason: "reason_code=team_mismatch")
        }

        if let systemIdentifier = systemIdentity.identifier,
           let bundledIdentifier = bundledIdentity.identifier,
           systemIdentifier != bundledIdentifier
        {
            return .untrusted(reason: "reason_code=identifier_mismatch")
        }

        return .trusted
    }

    private func signingIdentity(forPath path: String) -> SigningIdentity? {
        var staticCode: SecStaticCode?
        let url = URL(fileURLWithPath: path) as CFURL
        let createStatus = SecStaticCodeCreateWithPath(url, [], &staticCode)

        guard createStatus == errSecSuccess, let staticCode else {
            return nil
        }

        var infoDict: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &infoDict
        )
        guard infoStatus == errSecSuccess,
              let info = infoDict as? [String: Any]
        else {
            return nil
        }

        return SigningIdentity(
            identifier: info[kSecCodeInfoIdentifier as String] as? String,
            teamIdentifier: info[kSecCodeInfoTeamIdentifier as String] as? String
        )
    }
}
