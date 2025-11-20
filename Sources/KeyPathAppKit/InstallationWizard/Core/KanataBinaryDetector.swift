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
      }
    }

    /// Detailed description for troubleshooting
    var detailedDescription: String {
      switch status {
      case .systemInstalled:
        "Kanata is properly installed at system location and ready for LaunchDaemon use"
      case .bundledAvailable:
        "Kanata binary is bundled with the app and ready for SMAppService (via BundleProgram)"
      case .bundledUnsigned:
        "Kanata binary found but lacks proper Developer ID signature"
      case .missing:
        "No kanata binary found in expected locations"
      }
    }
  }

  /// Status of kanata binary detection
  enum KanataBinaryStatus {
    case systemInstalled  // Properly installed at /Library/KeyPath/bin/kanata
    case bundledAvailable  // Available in app bundle, can be installed
    case bundledUnsigned  // Available but unsigned
    case missing  // Not found anywhere
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

    // Priority 3: Not found
    AppLogger.shared.log("❌ [KanataBinaryDetector] No kanata binary found")
    return DetectionResult(
      status: .missing,
      path: nil,
      signingStatus: nil,
      isReady: false
    )
  }

  /// Check if kanata needs installation (for auto-fix logic)
  /// With SMAppService, bundled Kanata is sufficient (via BundleProgram).
  func needsInstallation() -> Bool {
    let result = detectCurrentStatus()
    // Bundled Kanata with proper signature is ready for SMAppService
    return result.status == .missing || result.status == .bundledUnsigned
  }

  /// Check if Kanata binary is installed and ready for use
  /// With SMAppService, bundled Kanata is considered installed.
  func isInstalled() -> Bool {
    let result = detectCurrentStatus()
    // Bundled Kanata with proper signature is ready for SMAppService
    return result.status == .bundledAvailable || result.status == .systemInstalled
  }

  /// Get recommended installation action
  /// With SMAppService, no action needed if bundled Kanata is available.
  func getRecommendedAction() -> ComponentRequirement? {
    let result = detectCurrentStatus()

    switch result.status {
    case .bundledAvailable, .systemInstalled:
      return nil  // No action needed
    case .bundledUnsigned:
      return .kanataBinaryMissing  // Needs proper signature
    case .missing:
      return .kanataBinaryMissing  // Needs installation
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
  /// With SMAppService, bundled Kanata is considered installed.
  func getMissingComponents() -> [ComponentRequirement] {
    let result = detectCurrentStatus()

    switch result.status {
    case .bundledAvailable, .systemInstalled:
      return []  // No missing components
    case .bundledUnsigned, .missing:
      return [.kanataBinaryMissing]
    }
  }

  /// Convert detection result to installed components for SystemStatusChecker
  func getInstalledComponents() -> [ComponentRequirement] {
    let result = detectCurrentStatus()

    switch result.status {
    case .systemInstalled:
      return []  // Use the absence of .kanataBinaryMissing to indicate "installed"
    case .bundledAvailable, .bundledUnsigned, .missing:
      return []
    }
  }
}
