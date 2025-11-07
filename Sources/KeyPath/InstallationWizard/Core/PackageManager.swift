import Foundation
import KeyPathCore
import Security

/// Manages package installation via Homebrew and other package managers
/// Implements the package management integration identified in the installer improvement analysis
class PackageManager {
    // MARK: - Types

    enum InstallationResult {
        case success
        case failure(reason: String)
        case homebrewNotAvailable
        case packageNotFound
        case userCancelled
    }

    enum PackageManagerType {
        case homebrew
        case unknown

        var displayName: String {
            switch self {
            case .homebrew: "Homebrew"
            case .unknown: "Unknown"
            }
        }
    }

    struct PackageInfo {
        let name: String
        let homebrewFormula: String?
        let description: String
        let isRequired: Bool

        static let kanata = PackageInfo(
            name: "Kanata",
            homebrewFormula: "kanata",
            description: "Keyboard remapping engine",
            isRequired: true
        )

        static let karabinerElements = PackageInfo(
            name: "Karabiner-Elements",
            homebrewFormula: nil, // Not available via Homebrew - manual download required
            description: "Virtual HID device driver",
            isRequired: true
        )
    }

    // MARK: - Homebrew Detection

    /// Checks if Homebrew is installed on the system
    func checkHomebrewInstallation() -> Bool {
        // Check both ARM and Intel Homebrew locations
        let homebrewPaths = [
            "/opt/homebrew/bin/brew", // ARM Homebrew
            "/usr/local/bin/brew" // Intel Homebrew
        ]

        for path in homebrewPaths where FileManager.default.fileExists(atPath: path) {
            AppLogger.shared.log("✅ [PackageManager] Homebrew found at: \(path)")
            return true
        }

        AppLogger.shared.log("❌ [PackageManager] Homebrew not found in standard locations")
        return false
    }

    /// Convenience method to check if the package manager (Homebrew) is installed
    func isInstalled() -> Bool {
        checkHomebrewInstallation()
    }

    /// Gets the Homebrew executable path
    func getHomebrewPath() -> String? {
        let homebrewPaths = [
            "/opt/homebrew/bin/brew", // ARM Homebrew (preferred)
            "/usr/local/bin/brew" // Intel Homebrew
        ]

        for path in homebrewPaths where FileManager.default.fileExists(atPath: path) {
            return path
        }

        return nil
    }

    /// Gets the Homebrew bin directory for installed packages
    func getHomebrewBinPath() -> String? {
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
            return "/opt/homebrew/bin" // ARM Homebrew
        } else if FileManager.default.fileExists(atPath: "/usr/local/bin/brew") {
            return "/usr/local/bin" // Intel Homebrew
        }

        return nil
    }

    // MARK: - Package Detection

    /// Checks if Kanata is installed via any method
    func detectKanataInstallation() -> KanataInstallationInfo {
        let possiblePaths = [
            WizardSystemPaths.kanataSystemInstallPath, // System-installed kanata (highest priority)
            WizardSystemPaths.bundledKanataPath, // Bundled kanata (preferred for detection)
            "/opt/homebrew/bin/kanata", // ARM Homebrew
            "/usr/local/bin/kanata", // Intel Homebrew
            "\(NSHomeDirectory())/.cargo/bin/kanata" // Rust cargo installation
        ]

        for path in possiblePaths where FileManager.default.fileExists(atPath: path) {
            let installationType = determineInstallationType(path: path)
            let codeSigningStatus = detectCodeSigningStatus(at: path)
            AppLogger.shared.log("✅ [PackageManager] Kanata found at: \(path) (\(installationType)), signing: \(codeSigningStatus)")

            return KanataInstallationInfo(
                isInstalled: true,
                path: path,
                installationType: installationType,
                version: getKanataVersion(at: path),
                codeSigningStatus: codeSigningStatus
            )
        }

        AppLogger.shared.log("❌ [PackageManager] Kanata not found in any standard location")
        return KanataInstallationInfo(
            isInstalled: false,
            path: nil,
            installationType: .notInstalled,
            version: nil,
            codeSigningStatus: .invalid(reason: "not found")
        )
    }

    private func determineInstallationType(path: String) -> KanataInstallationType {
        if path == WizardSystemPaths.kanataSystemInstallPath {
            .bundled // System-installed kanata is treated as bundled (installed by KeyPath)
        } else if path == WizardSystemPaths.bundledKanataPath {
            .bundled
        } else if path.contains("/opt/homebrew/bin") || path.contains("/usr/local/bin") {
            .homebrew
        } else if path.contains("/.cargo/bin") {
            .cargo
        } else {
            .manual
        }
    }

    /// Detect the code signing status of a kanata binary
    /// Public wrapper for code signing detection
    func getCodeSigningStatus(at path: String) -> CodeSigningStatus {
        detectCodeSigningStatus(at: path)
    }

    private func detectCodeSigningStatus(at path: String) -> CodeSigningStatus {
        let url = URL(fileURLWithPath: path) as CFURL

        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url, SecCSFlags(), &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            let message = SecCopyErrorMessageString(createStatus, nil) as String? ?? "OSStatus=\(createStatus)"
            AppLogger.shared.log("❌ [PackageManager] SecStaticCodeCreateWithPath failed for \(path): \(message)")
            return .invalid(reason: message)
        }

        // Validate the code signature (no explicit requirement; default validation)
        var cfError: Unmanaged<CFError>?
        let validity = SecStaticCodeCheckValidityWithErrors(staticCode, SecCSFlags(), nil, &cfError)

        // Extract signing information regardless of validity result when possible
        var infoDict: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &infoDict)
        let info = infoDict as? [String: Any]

        if validity == errSecSuccess {
            // Determine if Developer ID (presence of a certificate chain implies not ad hoc)
            if let certs = info?[kSecCodeInfoCertificates as String] as? [SecCertificate], let first = certs.first {
                var commonName: CFString?
                SecCertificateCopyCommonName(first, &commonName)
                let authority = (commonName as String?) ?? "Developer ID Application"
                return .developerIDSigned(authority: authority)
            } else {
                // Valid but no certificates → ad hoc
                return .adhocSigned
            }
        } else {
            // Determine if completely unsigned vs invalid
            let reason: String = if let err = cfError?.takeRetainedValue() {
                CFErrorCopyDescription(err) as String
            } else {
                "OSStatus=\(validity)"
            }

            // If there is no signing information at all, treat as unsigned
            if infoStatus != errSecSuccess || info?[kSecCodeInfoCertificates as String] == nil {
                // Heuristic: missing certificates likely means unsigned
                if reason.lowercased().contains("not signed") || reason.lowercased().contains("code object is not signed") {
                    return .unsigned
                }
            }
            return .invalid(reason: reason)
        }
    }

    private func getKanataVersion(at path: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = ["--version"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                return output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            AppLogger.shared.log("⚠️ [PackageManager] Could not get Kanata version: \(error)")
        }

        return nil
    }

    // MARK: - Package Installation

    /// Installs Kanata via Homebrew
    func installKanataViaBrew() async -> InstallationResult {
        AppLogger.shared.log("🔧 [PackageManager] Installing Kanata via Homebrew...")

        // Pre-installation validation
        guard checkHomebrewInstallation() else {
            AppLogger.shared.log("❌ [PackageManager] Homebrew not available")
            detectCommonIssues() // Log what might be wrong
            return .homebrewNotAvailable
        }

        guard let brewPath = getHomebrewPath() else {
            AppLogger.shared.log("❌ [PackageManager] Could not find Homebrew executable")
            return .homebrewNotAvailable
        }

        // Check if Kanata is already installed to avoid unnecessary work
        let existingInstallation = detectKanataInstallation()
        if existingInstallation.isInstalled {
            AppLogger.shared.log(
                "ℹ️ [PackageManager] Kanata already installed: \(existingInstallation.description)")
            return .success
        }

        // Pre-check if formula is available
        AppLogger.shared.log("🔍 [PackageManager] Checking if Kanata formula is available...")
        if !checkBrewFormulaAvailability(formula: "kanata") {
            AppLogger.shared.log(
                "❌ [PackageManager] Kanata formula not found - may need 'brew update' first")
            return .packageNotFound
        }

        AppLogger.shared.log("🔧 [PackageManager] Starting Kanata installation using: \(brewPath)")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: brewPath)
        task.arguments = ["install", "kanata"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus == 0 {
                AppLogger.shared.log("✅ [PackageManager] Homebrew installation completed successfully")
                AppLogger.shared.log("📝 [PackageManager] Installation output: \(output)")

                // Post-installation verification
                AppLogger.shared.log("🔍 [PackageManager] Verifying Kanata installation...")
                let verificationResult = detectKanataInstallation()

                if verificationResult.isInstalled {
                    AppLogger.shared.log(
                        "✅ [PackageManager] Installation verified: \(verificationResult.description)")
                    return .success
                } else {
                    AppLogger.shared.log(
                        "❌ [PackageManager] Installation completed but Kanata binary not detected")
                    detectCommonIssues() // Log potential issues
                    return .failure(
                        reason:
                        "Installation completed but binary not found - possible PATH or installation issue")
                }
            } else {
                AppLogger.shared.log(
                    "❌ [PackageManager] Homebrew installation failed with status \(task.terminationStatus)")
                AppLogger.shared.log("📝 [PackageManager] Error output: \(output)")

                // Analyze common installation failures
                analyzeInstallationFailure(output: output, exitCode: task.terminationStatus)

                return .failure(reason: "Homebrew installation failed: \(output)")
            }
        } catch {
            AppLogger.shared.log("❌ [PackageManager] Error running Homebrew: \(error)")
            return .failure(reason: "Error running Homebrew: \(error.localizedDescription)")
        }
    }

    /// Checks if a Homebrew formula is available
    func checkBrewFormulaAvailability(formula: String) -> Bool {
        guard let brewPath = getHomebrewPath() else {
            return false
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: brewPath)
        task.arguments = ["search", formula]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            let isAvailable = task.terminationStatus == 0 && output.contains(formula)
            AppLogger.shared.log("🔍 [PackageManager] Formula '\(formula)' available: \(isAvailable)")
            return isAvailable
        } catch {
            AppLogger.shared.log("❌ [PackageManager] Error checking formula availability: \(error)")
            return false
        }
    }

    // MARK: - System Information

    /// Gets comprehensive package manager information
    func getPackageManagerInfo() -> PackageManagerInfo {
        AppLogger.shared.log("🔍 [PackageManager] Gathering package manager information")

        let homebrewAvailable = checkHomebrewInstallation()
        let homebrewPath = getHomebrewPath()
        let homebrewBinPath = getHomebrewBinPath()
        let kanataInfo = detectKanataInstallation()

        // Log potential issues
        if !homebrewAvailable {
            AppLogger.shared.log(
                "⚠️ [PackageManager] No package manager detected - automatic installation not available")
        }

        if !kanataInfo.isInstalled {
            AppLogger.shared.log("⚠️ [PackageManager] Kanata binary not detected in any standard location")

            // Check for common installation issues
            detectCommonIssues()
        }

        AppLogger.shared.log(
            "📊 [PackageManager] Package manager summary: Homebrew=\(homebrewAvailable), Kanata=\(kanataInfo.isInstalled)"
        )

        return PackageManagerInfo(
            homebrewAvailable: homebrewAvailable,
            homebrewPath: homebrewPath,
            homebrewBinPath: homebrewBinPath,
            kanataInstallation: kanataInfo,
            supportedPackageManagers: homebrewAvailable ? [.homebrew] : []
        )
    }

    /// Detects common package management issues and logs them
    private func detectCommonIssues() {
        AppLogger.shared.log("🔍 [PackageManager] Detecting common installation issues")

        // Check for common PATH issues
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let homebrewPaths = ["/opt/homebrew/bin", "/usr/local/bin"]

        for homebrewPath in homebrewPaths where !pathEnv.contains(homebrewPath) {
            AppLogger.shared.log(
                "⚠️ [PackageManager] PATH may be missing \(homebrewPath) - this could prevent detection")
        }

        // Check for partial Homebrew installation
        let homebrewDirs = ["/opt/homebrew", "/usr/local/Homebrew"]
        for dir in homebrewDirs {
            if FileManager.default.fileExists(atPath: dir),
               !FileManager.default.fileExists(atPath: "\(dir)/bin/brew") {
                AppLogger.shared.log(
                    "⚠️ [PackageManager] Found \(dir) but no brew executable - possible incomplete installation"
                )
            }
        }

        // Check for Cargo installation without Kanata
        let cargoPath = "\(NSHomeDirectory())/.cargo/bin"
        if FileManager.default.fileExists(atPath: cargoPath),
           !FileManager.default.fileExists(atPath: "\(cargoPath)/kanata") {
            AppLogger.shared.log(
                "ℹ️ [PackageManager] Cargo detected but no Kanata binary - user may need to install via 'cargo install kanata'"
            )
        }

        // Check for Homebrew but no Kanata formula
        if checkHomebrewInstallation(), !checkBrewFormulaAvailability(formula: "kanata") {
            AppLogger.shared.log(
                "⚠️ [PackageManager] Homebrew available but Kanata formula not found - may need tap update")
        }
    }

    /// Analyzes installation failures and logs potential solutions
    private func analyzeInstallationFailure(output: String, exitCode: Int32) {
        AppLogger.shared.log(
            "🔍 [PackageManager] Analyzing installation failure (exit code: \(exitCode))")

        let outputLower = output.lowercased()

        // Common Homebrew installation issues
        if outputLower.contains("permission denied") || outputLower.contains("operation not permitted") {
            AppLogger.shared.log(
                "⚠️ [PackageManager] Permission issue detected - may need to fix Homebrew permissions")
            AppLogger.shared.log(
                "💡 [PackageManager] Suggested fix: sudo chown -R $(whoami) /opt/homebrew || /usr/local")
        }

        if outputLower.contains("no such file or directory") && outputLower.contains("xcode") {
            AppLogger.shared.log("⚠️ [PackageManager] Xcode command line tools issue detected")
            AppLogger.shared.log("💡 [PackageManager] Suggested fix: xcode-select --install")
        }

        if outputLower.contains("network") || outputLower.contains("connection")
            || outputLower.contains("timeout") {
            AppLogger.shared.log("⚠️ [PackageManager] Network connectivity issue detected")
            AppLogger.shared.log("💡 [PackageManager] Check internet connection and try again")
        }

        if outputLower.contains("formula") && outputLower.contains("not found") {
            AppLogger.shared.log("⚠️ [PackageManager] Formula not found - may need to update Homebrew")
            AppLogger.shared.log("💡 [PackageManager] Suggested fix: brew update")
        }

        if outputLower.contains("disk") || outputLower.contains("space")
            || outputLower.contains("no space left") {
            AppLogger.shared.log("⚠️ [PackageManager] Disk space issue detected")
            AppLogger.shared.log("💡 [PackageManager] Free up disk space and try again")
        }

        if exitCode == 1, outputLower.contains("already installed") {
            AppLogger.shared.log(
                "ℹ️ [PackageManager] Package may already be installed but not detected in PATH")
        }
    }

    /// Gets installation recommendations based on current system state
    func getInstallationRecommendations() -> [InstallationRecommendation] {
        var recommendations: [InstallationRecommendation] = []

        let kanataInfo = detectKanataInstallation()

        // Kanata recommendations
        if !kanataInfo.isInstalled {
            if checkHomebrewInstallation() {
                recommendations.append(
                    InstallationRecommendation(
                        package: .kanata,
                        method: .homebrew,
                        priority: .high,
                        command: "brew install kanata",
                        description: "Install Kanata keyboard remapping engine via Homebrew"
                    ))
            } else {
                recommendations.append(
                    InstallationRecommendation(
                        package: .kanata,
                        method: .manual,
                        priority: .high,
                        command: "Download from GitHub releases",
                        description: "Install Homebrew first, then install Kanata"
                    ))
            }
        }

        // Karabiner-Elements recommendations (always manual)
        recommendations.append(
            InstallationRecommendation(
                package: .karabinerElements,
                method: .manual,
                priority: .high,
                command: "Download from website",
                description: "Install Karabiner-Elements for virtual HID device support"
            ))

        return recommendations
    }
}

// MARK: - Supporting Types

enum KanataInstallationType {
    case bundled
    case homebrew
    case cargo
    case manual
    case notInstalled

    var displayName: String {
        switch self {
        case .bundled: "Bundled"
        case .homebrew: "Homebrew"
        case .cargo: "Cargo (Rust)"
        case .manual: "Manual"
        case .notInstalled: "Not Installed"
        }
    }
}

/// Code signing status of a kanata binary
enum CodeSigningStatus {
    case developerIDSigned(authority: String)
    case adhocSigned
    case unsigned
    case invalid(reason: String)

    var isDeveloperID: Bool {
        if case .developerIDSigned = self { return true }
        return false
    }
}

struct KanataInstallationInfo {
    let isInstalled: Bool
    let path: String?
    let installationType: KanataInstallationType
    let version: String?
    let codeSigningStatus: CodeSigningStatus

    var needsReplacement: Bool {
        !codeSigningStatus.isDeveloperID
    }

    var description: String {
        if isInstalled, let path {
            let versionInfo = version ?? "Unknown version"
            let signing = switch codeSigningStatus {
            case let .developerIDSigned(authority): "Signed: \(authority)"
            case .adhocSigned: "Signed: ad hoc"
            case .unsigned: "Unsigned"
            case let .invalid(reason): "Invalid signature (\(reason))"
            }
            return "Installed at \(path) (\(installationType.displayName)) - \(versionInfo) - \(signing)"
        } else {
            return "Not installed"
        }
    }
}

struct PackageManagerInfo {
    let homebrewAvailable: Bool
    let homebrewPath: String?
    let homebrewBinPath: String?
    let kanataInstallation: KanataInstallationInfo
    let supportedPackageManagers: [PackageManager.PackageManagerType]

    var description: String {
        var info = """
        Package Manager Information:
        - Homebrew Available: \(homebrewAvailable)
        """

        if let path = homebrewPath {
            info += "\n- Homebrew Path: \(path)"
        }

        if let binPath = homebrewBinPath {
            info += "\n- Homebrew Bin Path: \(binPath)"
        }

        info += "\n- Kanata: \(kanataInstallation.description)"

        return info
    }
}

enum InstallationMethod {
    case homebrew
    case manual
    case cargo

    var displayName: String {
        switch self {
        case .homebrew: "Homebrew"
        case .manual: "Manual Download"
        case .cargo: "Cargo (Rust)"
        }
    }
}

enum InstallationPriority {
    case high
    case medium
    case low

    var displayName: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }
}

struct InstallationRecommendation {
    let package: PackageManager.PackageInfo
    let method: InstallationMethod
    let priority: InstallationPriority
    let command: String
    let description: String

    var displayText: String {
        """
        \(package.name) (\(priority.displayName) Priority)
        Method: \(method.displayName)
        Command: \(command)
        Description: \(description)
        """
    }
}
