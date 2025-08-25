import Foundation

/// Manages macOS version detection and system requirements validation
/// Implements version-specific driver handling as identified in the installer improvement analysis
class SystemRequirements {
    // MARK: - Types

    /// macOS version categories for driver compatibility
    enum MacOSVersion: Equatable {
        case legacy(version: String) // ≤10.x - kernel extension
        case modern(version: String) // ≥11.x - DriverKit
        case unknown(version: String)

        var isModern: Bool {
            switch self {
            case .modern: true
            case .legacy, .unknown: false
            }
        }

        var isLegacy: Bool {
            switch self {
            case .legacy: true
            case .modern, .unknown: false
            }
        }

        var versionString: String {
            switch self {
            case let .legacy(version), let .modern(version), let .unknown(version):
                version
            }
        }
    }

    /// Driver types based on macOS version
    enum DriverType: Equatable {
        case driverKit // macOS 11+ - Karabiner DriverKit VirtualHIDDevice (V5)
        case kernelExtension // macOS 10 - Karabiner kernel extension (legacy)
        case unknown

        var displayName: String {
            switch self {
            case .driverKit: "DriverKit VirtualHIDDevice"
            case .kernelExtension: "Kernel Extension VirtualHIDDevice"
            case .unknown: "Unknown Driver Type"
            }
        }

        var description: String {
            switch self {
            case .driverKit:
                "Modern DriverKit-based virtual HID device driver for macOS 11 and later"
            case .kernelExtension:
                "Legacy kernel extension-based virtual HID device driver for macOS 10"
            case .unknown:
                "Unable to determine appropriate driver type for this macOS version"
            }
        }
    }

    /// System compatibility validation result
    struct ValidationResult {
        let isCompatible: Bool
        let macosVersion: MacOSVersion
        let requiredDriverType: DriverType
        let issues: [String]
        let recommendations: [String]

        var description: String {
            var result = """
            System Compatibility Check:
            - macOS Version: \(macosVersion.versionString) (\(macosVersion.isModern ? "Modern" : "Legacy"))
            - Required Driver: \(requiredDriverType.displayName)
            - Compatible: \(isCompatible)
            """

            if !issues.isEmpty {
                result += "\n\nIssues:\n" + issues.map { "- \($0)" }.joined(separator: "\n")
            }

            if !recommendations.isEmpty {
                result +=
                    "\n\nRecommendations:\n" + recommendations.map { "- \($0)" }.joined(separator: "\n")
            }

            return result
        }
    }

    // MARK: - Detection Methods

    /// Detects the current macOS version
    func detectMacOSVersion() -> MacOSVersion {
        let processInfo = ProcessInfo.processInfo
        let version = processInfo.operatingSystemVersion

        let versionString = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"

        AppLogger.shared.log("🔍 [SystemRequirements] Detected macOS version: \(versionString)")

        // Determine version category based on major version
        if version.majorVersion >= 11 {
            return .modern(version: versionString)
        } else if version.majorVersion == 10 {
            return .legacy(version: versionString)
        } else {
            AppLogger.shared.log("⚠️ [SystemRequirements] Unknown macOS version: \(versionString)")
            return .unknown(version: versionString)
        }
    }

    /// Determines the required driver type based on macOS version
    func getRequiredDriverType() -> DriverType {
        let macosVersion = detectMacOSVersion()
        return getRequiredDriverType(for: macosVersion)
    }

    /// Determines the required driver type for a specific macOS version
    func getRequiredDriverType(for version: MacOSVersion) -> DriverType {
        switch version {
        case .modern:
            .driverKit
        case .legacy:
            .kernelExtension
        case .unknown:
            .unknown
        }
    }

    /// Validates system compatibility for KeyPath installation
    func validateSystemCompatibility() -> ValidationResult {
        AppLogger.shared.log("🔍 [SystemRequirements] Validating system compatibility")

        let macosVersion = detectMacOSVersion()
        let requiredDriverType = getRequiredDriverType(for: macosVersion)

        var issues: [String] = []
        var recommendations: [String] = []
        var isCompatible = true

        // Check macOS version compatibility
        switch macosVersion {
        case let .modern(version):
            AppLogger.shared.log("✅ [SystemRequirements] Modern macOS detected: \(version)")
            recommendations.append("Use Karabiner-Elements DriverKit version for optimal compatibility")

        case let .legacy(version):
            AppLogger.shared.log("⚠️ [SystemRequirements] Legacy macOS detected: \(version)")
            issues.append("macOS 10.x detected - legacy kernel extension support required")
            recommendations.append("Consider upgrading to macOS 11 or later for better driver support")
            recommendations.append("Use Karabiner-Elements with kernel extension support")

        case let .unknown(version):
            AppLogger.shared.log("❌ [SystemRequirements] Unknown macOS version: \(version)")
            issues.append("Unknown macOS version detected: \(version)")
            isCompatible = false
            recommendations.append("Verify macOS version compatibility before proceeding")
        }

        // Check minimum system requirements
        let processInfo = ProcessInfo.processInfo
        let version = processInfo.operatingSystemVersion

        // KeyPath requires macOS 13.0+ based on CLAUDE.md
        if version.majorVersion < 13 {
            issues.append(
                "KeyPath requires macOS 13.0 or later (detected: \(macosVersion.versionString))")
            isCompatible = false
            recommendations.append("Upgrade to macOS 13.0 or later")
        }

        // Check for specific version compatibility issues
        if case .legacy = macosVersion {
            // Legacy versions have additional considerations
            issues.append("Legacy macOS versions may require additional manual configuration")
            recommendations.append("Review legacy setup documentation")
        }

        let result = ValidationResult(
            isCompatible: isCompatible,
            macosVersion: macosVersion,
            requiredDriverType: requiredDriverType,
            issues: issues,
            recommendations: recommendations
        )

        AppLogger.shared.log(
            "🔍 [SystemRequirements] Compatibility check complete: \(isCompatible ? "✅ Compatible" : "❌ Not Compatible")"
        )
        if !issues.isEmpty {
            AppLogger.shared.log("⚠️ [SystemRequirements] Issues found: \(issues.joined(separator: ", "))")
        }

        return result
    }

    // MARK: - Driver-Specific Methods

    /// Checks if the current system supports DriverKit
    func supportsDriverKit() -> Bool {
        let version = detectMacOSVersion()
        return version.isModern
    }

    /// Checks if the current system requires kernel extensions
    func requiresKernelExtension() -> Bool {
        let version = detectMacOSVersion()
        return version.isLegacy
    }

    /// Gets driver-specific installation instructions
    func getDriverInstallationInstructions() -> DriverInstallationInstructions {
        let driverType = getRequiredDriverType()

        switch driverType {
        case .driverKit:
            return DriverInstallationInstructions(
                driverType: driverType,
                steps: [
                    "Download Karabiner-Elements from the official website",
                    "Install Karabiner-Elements using the provided installer",
                    "Enable the DriverKit extension in System Settings > Privacy & Security > Driver Extensions",
                    "Grant necessary permissions in System Settings > Privacy & Security"
                ],
                requirements: [
                    "macOS 11.0 or later",
                    "Admin privileges for installation",
                    "System restart may be required"
                ],
                notes: [
                    "DriverKit provides better security and stability than kernel extensions",
                    "No kernel extension loading required"
                ]
            )

        case .kernelExtension:
            return DriverInstallationInstructions(
                driverType: driverType,
                steps: [
                    "Download Karabiner-Elements with kernel extension support",
                    "Install Karabiner-Elements using the provided installer",
                    "Allow kernel extension loading in System Preferences > Security & Privacy",
                    "Restart the system to load the kernel extension",
                    "Grant necessary permissions in System Preferences > Security & Privacy"
                ],
                requirements: [
                    "macOS 10.x",
                    "Admin privileges for installation",
                    "System restart required",
                    "Kernel extension approval required"
                ],
                notes: [
                    "Kernel extensions require explicit user approval",
                    "System restart is mandatory for kernel extension loading",
                    "Consider upgrading to macOS 11+ for DriverKit support"
                ]
            )

        case .unknown:
            return DriverInstallationInstructions(
                driverType: driverType,
                steps: [
                    "Verify macOS version compatibility",
                    "Contact support for installation guidance"
                ],
                requirements: [
                    "Supported macOS version"
                ],
                notes: [
                    "Unable to determine installation steps for this macOS version"
                ]
            )
        }
    }

    // MARK: - System Information

    /// Gets comprehensive system information
    func getSystemInfo() -> SystemInfo {
        let macosVersion = detectMacOSVersion()
        let driverType = getRequiredDriverType()
        let validation = validateSystemCompatibility()

        return SystemInfo(
            macosVersion: macosVersion,
            requiredDriverType: driverType,
            compatibilityResult: validation,
            supportsDriverKit: supportsDriverKit(),
            requiresKernelExtension: requiresKernelExtension()
        )
    }

    // MARK: - Additional Permission Checks

    /// Checks if driver extension is enabled in System Settings
    func checkDriverExtensionEnabled() async -> Bool {
        // This would typically require checking System Extensions framework
        // For now, return true as a placeholder - implementation would require
        // SystemExtensions framework calls to check if Karabiner driver is enabled
        AppLogger.shared.log("🔍 [SystemRequirements] Checking driver extension status (placeholder)")
        return true
    }

    /// Checks if background services are enabled
    func checkBackgroundServicesEnabled() async -> Bool {
        // This would typically check Login Items and launch agents
        // For now, return true as a placeholder - implementation would require
        // checking specific Karabiner background services in Login Items
        AppLogger.shared.log("🔍 [SystemRequirements] Checking background services status (placeholder)")
        return true
    }
}

// MARK: - Supporting Types

/// Driver installation instructions
struct DriverInstallationInstructions {
    let driverType: SystemRequirements.DriverType
    let steps: [String]
    let requirements: [String]
    let notes: [String]

    var description: String {
        var result = """
        Installation Instructions for \(driverType.displayName):

        Steps:
        """

        for (index, step) in steps.enumerated() {
            result += "\n\(index + 1). \(step)"
        }

        result += "\n\nRequirements:"
        for requirement in requirements {
            result += "\n- \(requirement)"
        }

        if !notes.isEmpty {
            result += "\n\nNotes:"
            for note in notes {
                result += "\n- \(note)"
            }
        }

        return result
    }
}

/// Comprehensive system information
struct SystemInfo {
    let macosVersion: SystemRequirements.MacOSVersion
    let requiredDriverType: SystemRequirements.DriverType
    let compatibilityResult: SystemRequirements.ValidationResult
    let supportsDriverKit: Bool
    let requiresKernelExtension: Bool

    var description: String {
        """
        System Information:
        - macOS Version: \(macosVersion.versionString) (\(macosVersion.isModern ? "Modern" : "Legacy"))
        - Required Driver: \(requiredDriverType.displayName)
        - DriverKit Support: \(supportsDriverKit)
        - Kernel Extension Required: \(requiresKernelExtension)
        - System Compatible: \(compatibilityResult.isCompatible)
        """
    }
}
