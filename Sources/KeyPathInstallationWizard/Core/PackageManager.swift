import Foundation
import KeyPathCore
import os.lock
import Security

/// Manages package installation via Homebrew and other package managers
/// Implements the package management integration identified in the installer improvement analysis
public class PackageManager {
    public init() {}
    // MARK: - Code Signing Cache

    /// Cache for code signing status to avoid expensive Security framework calls
    /// Cache key: file path
    /// Cache value: (status, modificationDate, fileSize)
    private struct CacheEntry: Sendable {
        let status: CodeSigningStatus
        let modificationDate: Date
        let fileSize: Int64
    }

    /// Maximum number of entries in the code signing cache (LRU eviction)
    private static let maxCacheSize = 50

    /// Thread-safe LRU cache state protected by OSAllocatedUnfairLock.
    /// Both the dictionary and access-order array live inside the lock's state
    /// so they are always mutated atomically under a single lock acquisition.
    private struct CacheState: Sendable {
        var entries: [String: CacheEntry] = [:]
        /// Tracks access order for LRU eviction (most recently used at end)
        var accessOrder: [String] = []
    }

    private static let cache = OSAllocatedUnfairLock(initialState: CacheState())

    // MARK: - Types

    public enum InstallationResult {
        case success
        case failure(reason: String)
        case homebrewNotAvailable
        case packageNotFound
        case userCancelled
    }

    public enum PackageManagerType {
        case homebrew
        case unknown

        public var displayName: String {
            switch self {
            case .homebrew: "Homebrew"
            case .unknown: "Unknown"
            }
        }
    }

    public struct PackageInfo: Sendable {
        public let name: String
        public let homebrewFormula: String?
        public let description: String
        public let isRequired: Bool

        public static let kanata = PackageInfo(
            name: "Kanata",
            homebrewFormula: "kanata",
            description: "Keyboard remapping engine",
            isRequired: true
        )

        public static let karabinerElements = PackageInfo(
            name: "Karabiner-Elements",
            homebrewFormula: nil,
            description: "VirtualHID driver and background services required for Kanata",
            isRequired: true
        )
    }

    // MARK: - Homebrew Detection

    /// Checks if Homebrew is installed on the system
    public func checkHomebrewInstallation() -> Bool {
        // Check both ARM and Intel Homebrew locations
        let homebrewPaths = [
            "/opt/homebrew/bin/brew", // ARM Homebrew
            "/usr/local/bin/brew" // Intel Homebrew
        ]

        for path in homebrewPaths where Foundation.FileManager().fileExists(atPath: path) {
            AppLogger.shared.log("✅ [PackageManager] Homebrew found at: \(path)")
            return true
        }

        AppLogger.shared.log("❌ [PackageManager] Homebrew not found in standard locations")
        return false
    }

    /// Convenience method to check if the package manager (Homebrew) is installed
    public func isInstalled() -> Bool {
        checkHomebrewInstallation()
    }

    /// Gets the Homebrew executable path
    public func getHomebrewPath() -> String? {
        let homebrewPaths = [
            "/opt/homebrew/bin/brew", // ARM Homebrew (preferred)
            "/usr/local/bin/brew" // Intel Homebrew
        ]

        for path in homebrewPaths where Foundation.FileManager().fileExists(atPath: path) {
            return path
        }

        return nil
    }

    /// Gets the Homebrew bin directory for installed packages
    public func getHomebrewBinPath() -> String? {
        if Foundation.FileManager().fileExists(atPath: "/opt/homebrew/bin/brew") {
            return "/opt/homebrew/bin" // ARM Homebrew
        } else if Foundation.FileManager().fileExists(atPath: "/usr/local/bin/brew") {
            return "/usr/local/bin" // Intel Homebrew
        }

        return nil
    }

    // MARK: - Package Detection

    /// Checks if Kanata is installed via any method
    public func detectKanataInstallation() async -> KanataInstallationInfo {
        let possiblePaths = [
            WizardSystemPaths.kanataSystemInstallPath, // System-installed kanata (highest priority)
            WizardSystemPaths.bundledKanataPath, // Bundled kanata (preferred for detection)
            "/opt/homebrew/bin/kanata", // ARM Homebrew
            "/usr/local/bin/kanata", // Intel Homebrew
            "\(NSHomeDirectory())/.cargo/bin/kanata" // Rust cargo installation
        ]

        for path in possiblePaths where Foundation.FileManager().fileExists(atPath: path) {
            let installationType = determineInstallationType(path: path)
            let codeSigningStatus = detectCodeSigningStatus(at: path)
            AppLogger.shared.log(
                "✅ [PackageManager] Kanata found at: \(path) (\(installationType)), signing: \(codeSigningStatus)"
            )

            return await KanataInstallationInfo(
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
    /// Caches results based on file modification date and size for performance
    public func getCodeSigningStatus(at path: String) -> CodeSigningStatus {
        // Read file attributes once (used for both cache validation and caching)
        guard let attributes = try? Foundation.FileManager().attributesOfItem(atPath: path),
              let modDate = attributes[FileAttributeKey.modificationDate] as? Date,
              let fileSize = attributes[FileAttributeKey.size] as? Int64
        else {
            // Can't cache without metadata - perform check and return
            return detectCodeSigningStatus(at: path)
        }

        // Check cache atomically (single lock acquisition for lookup + access-order update)
        enum CacheLookup {
            case hit(CodeSigningStatus)
            case stale
            case miss
        }

        let lookup: CacheLookup = Self.cache.withLock { state in
            if let cached = state.entries[path] {
                if modDate == cached.modificationDate, fileSize == cached.fileSize {
                    // Cache hit - update access order (move to end = most recently used)
                    if let index = state.accessOrder.firstIndex(of: path) {
                        state.accessOrder.remove(at: index)
                    }
                    state.accessOrder.append(path)
                    return .hit(cached.status)
                } else {
                    // Stale entry - remove it atomically
                    state.entries.removeValue(forKey: path)
                    state.accessOrder.removeAll { $0 == path }
                    return .stale
                }
            }
            return .miss
        }

        switch lookup {
        case let .hit(status):
            AppLogger.shared.log("✅ [PackageManager] Code signing cache hit for \(path)")
            return status
        case .stale:
            AppLogger.shared.log(
                "🔄 [PackageManager] Code signing cache invalidated (file changed): \(path)"
            )
        case .miss:
            break
        }

        // Cache miss or invalidated - perform actual check
        let status = detectCodeSigningStatus(at: path)

        // Cache the result atomically (single lock acquisition for eviction + insert)
        Self.cache.withLock { state in
            // Evict oldest entry if cache is at capacity (LRU)
            if state.entries.count >= Self.maxCacheSize {
                if let oldestPath = state.accessOrder.first {
                    state.entries.removeValue(forKey: oldestPath)
                    state.accessOrder.removeFirst()
                    AppLogger.shared.log("🗑️ [PackageManager] Evicted oldest cache entry: \(oldestPath)")
                }
            }

            // Add new entry
            state.entries[path] = CacheEntry(
                status: status,
                modificationDate: modDate,
                fileSize: fileSize
            )
            // Add to end of access order (most recently used)
            state.accessOrder.removeAll { $0 == path }
            state.accessOrder.append(path)
        }
        AppLogger.shared.log("💾 [PackageManager] Cached code signing status for \(path)")

        return status
    }

    private func detectCodeSigningStatus(at path: String) -> CodeSigningStatus {
        let url = URL(fileURLWithPath: path) as CFURL

        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url, SecCSFlags(), &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            let message =
                SecCopyErrorMessageString(createStatus, nil) as String? ?? "OSStatus=\(createStatus)"
            AppLogger.shared.log(
                "❌ [PackageManager] SecStaticCodeCreateWithPath failed for \(path): \(message)"
            )
            return .invalid(reason: message)
        }

        // Validate the code signature (no explicit requirement; default validation)
        var cfError: Unmanaged<CFError>?
        let validity = SecStaticCodeCheckValidityWithErrors(staticCode, SecCSFlags(), nil, &cfError)

        // Extract signing information regardless of validity result when possible
        var infoDict: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &infoDict
        )
        let info = infoDict as? [String: Any]

        if validity == errSecSuccess {
            // Determine if Developer ID (presence of a certificate chain implies not ad hoc)
            if let certs = info?[kSecCodeInfoCertificates as String] as? [SecCertificate],
               let first = certs.first
            {
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
            let reason: String =
                if let err = cfError?.takeRetainedValue() {
                    CFErrorCopyDescription(err) as String
                } else {
                    "OSStatus=\(validity)"
                }

            // If there is no signing information at all, treat as unsigned
            if infoStatus != errSecSuccess || info?[kSecCodeInfoCertificates as String] == nil {
                // Heuristic: missing certificates likely means unsigned
                if reason.lowercased().contains("not signed")
                    || reason.lowercased().contains("code object is not signed")
                {
                    return .unsigned
                }
            }
            return .invalid(reason: reason)
        }
    }

    private func getKanataVersion(at path: String) async -> String? {
        do {
            let result = try await SubprocessRunner.shared.run(path, args: ["--version"], timeout: 10)
            if result.exitCode == 0 {
                return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            AppLogger.shared.log("⚠️ [PackageManager] Could not get Kanata version: \(error)")
        }
        return nil
    }

    // MARK: - Package Installation

    /// Installs Kanata via Homebrew
    public func installKanataViaBrew() async -> InstallationResult {
        AppLogger.shared.log("🔧 [PackageManager] Installing Kanata via Homebrew...")

        // Pre-installation validation
        guard checkHomebrewInstallation() else {
            AppLogger.shared.log("❌ [PackageManager] Homebrew not available")
            await detectCommonIssues() // Log what might be wrong
            return .homebrewNotAvailable
        }

        guard let brewPath = getHomebrewPath() else {
            AppLogger.shared.log("❌ [PackageManager] Could not find Homebrew executable")
            return .homebrewNotAvailable
        }

        // Check if Kanata is already installed to avoid unnecessary work
        let existingInstallation = await detectKanataInstallation()
        if existingInstallation.isInstalled {
            AppLogger.shared.log(
                "ℹ️ [PackageManager] Kanata already installed: \(existingInstallation.description)"
            )
            return .success
        }

        // Pre-check if formula is available
        AppLogger.shared.log("🔍 [PackageManager] Checking if Kanata formula is available...")
        if await !checkBrewFormulaAvailability(formula: "kanata") {
            AppLogger.shared.log(
                "❌ [PackageManager] Kanata formula not found - may need 'brew update' first"
            )
            return .packageNotFound
        }

        AppLogger.shared.log("🔧 [PackageManager] Starting Kanata installation using: \(brewPath)")

        do {
            // Homebrew install can take a while, use longer timeout (5 minutes)
            let result = try await SubprocessRunner.shared.run(
                brewPath,
                args: ["install", "kanata"],
                timeout: 300
            )
            let output = result.stdout + result.stderr

            if result.exitCode == 0 {
                AppLogger.shared.log("✅ [PackageManager] Homebrew installation completed successfully")
                AppLogger.shared.log("📝 [PackageManager] Installation output: \(output)")

                // Post-installation verification
                AppLogger.shared.log("🔍 [PackageManager] Verifying Kanata installation...")
                let verificationResult = await detectKanataInstallation()

                if verificationResult.isInstalled {
                    AppLogger.shared.log(
                        "✅ [PackageManager] Installation verified: \(verificationResult.description)"
                    )
                    return .success
                } else {
                    AppLogger.shared.log(
                        "❌ [PackageManager] Installation completed but Kanata binary not detected"
                    )
                    await detectCommonIssues() // Log potential issues
                    return .failure(
                        reason:
                        "Installation completed but binary not found - possible PATH or installation issue"
                    )
                }
            } else {
                AppLogger.shared.log(
                    "❌ [PackageManager] Homebrew installation failed with status \(result.exitCode)"
                )
                AppLogger.shared.log("📝 [PackageManager] Error output: \(output)")

                // Analyze common installation failures
                analyzeInstallationFailure(output: output, exitCode: result.exitCode)

                return .failure(reason: "Homebrew installation failed: \(output)")
            }
        } catch {
            AppLogger.shared.log("❌ [PackageManager] Error running Homebrew: \(error)")
            return .failure(reason: "Error running Homebrew: \(error.localizedDescription)")
        }
    }

    /// Checks if a Homebrew formula is available
    public func checkBrewFormulaAvailability(formula: String) async -> Bool {
        guard let brewPath = getHomebrewPath() else {
            return false
        }

        do {
            let result = try await SubprocessRunner.shared.run(
                brewPath,
                args: ["search", formula],
                timeout: 30
            )
            let output = result.stdout + result.stderr
            let isAvailable = result.exitCode == 0 && output.contains(formula)
            AppLogger.shared.log("🔍 [PackageManager] Formula '\(formula)' available: \(isAvailable)")
            return isAvailable
        } catch {
            AppLogger.shared.log("❌ [PackageManager] Error checking formula availability: \(error)")
            return false
        }
    }

    // MARK: - System Information

    /// Gets comprehensive package manager information
    public func getPackageManagerInfo() async -> PackageManagerInfo {
        AppLogger.shared.log("🔍 [PackageManager] Gathering package manager information")

        let homebrewAvailable = checkHomebrewInstallation()
        let homebrewPath = getHomebrewPath()
        let homebrewBinPath = getHomebrewBinPath()
        let kanataInfo = await detectKanataInstallation()

        // Log potential issues
        if !homebrewAvailable {
            AppLogger.shared.log(
                "⚠️ [PackageManager] No package manager detected - automatic installation not available"
            )
        }

        if !kanataInfo.isInstalled {
            AppLogger.shared.log("⚠️ [PackageManager] Kanata binary not detected in any standard location")

            // Check for common installation issues
            await detectCommonIssues()
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
    private func detectCommonIssues() async {
        AppLogger.shared.log("🔍 [PackageManager] Detecting common installation issues")

        // Check for common PATH issues
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let homebrewPaths = ["/opt/homebrew/bin", "/usr/local/bin"]

        for homebrewPath in homebrewPaths where !pathEnv.contains(homebrewPath) {
            AppLogger.shared.log(
                "⚠️ [PackageManager] PATH may be missing \(homebrewPath) - this could prevent detection"
            )
        }

        // Check for partial Homebrew installation
        let homebrewDirs = ["/opt/homebrew", "/usr/local/Homebrew"]
        for dir in homebrewDirs {
            if Foundation.FileManager().fileExists(atPath: dir),
               !Foundation.FileManager().fileExists(atPath: "\(dir)/bin/brew")
            {
                AppLogger.shared.log(
                    "⚠️ [PackageManager] Found \(dir) but no brew executable - possible incomplete installation"
                )
            }
        }

        // Check for Cargo installation without Kanata
        let cargoPath = "\(NSHomeDirectory())/.cargo/bin"
        if Foundation.FileManager().fileExists(atPath: cargoPath),
           !Foundation.FileManager().fileExists(atPath: "\(cargoPath)/kanata")
        {
            AppLogger.shared.log(
                "ℹ️ [PackageManager] Cargo detected but no Kanata binary - user may need to install via 'cargo install kanata'"
            )
        }

        // Check for Homebrew but no Kanata formula
        if checkHomebrewInstallation(), await !checkBrewFormulaAvailability(formula: "kanata") {
            AppLogger.shared.log(
                "⚠️ [PackageManager] Homebrew available but Kanata formula not found - may need tap update"
            )
        }
    }

    /// Analyzes installation failures and logs potential solutions
    private func analyzeInstallationFailure(output: String, exitCode: Int32) {
        AppLogger.shared.log(
            "🔍 [PackageManager] Analyzing installation failure (exit code: \(exitCode))"
        )

        let outputLower = output.lowercased()

        // Common Homebrew installation issues
        if outputLower.contains("permission denied") || outputLower.contains("operation not permitted") {
            AppLogger.shared.log(
                "⚠️ [PackageManager] Permission issue detected - may need to fix Homebrew permissions"
            )
            AppLogger.shared.log(
                "💡 [PackageManager] Suggested fix: sudo chown -R $(whoami) /opt/homebrew || /usr/local"
            )
        }

        if outputLower.contains("no such file or directory") && outputLower.contains("xcode") {
            AppLogger.shared.log("⚠️ [PackageManager] Xcode command line tools issue detected")
            AppLogger.shared.log("💡 [PackageManager] Suggested fix: xcode-select --install")
        }

        if outputLower.contains("network") || outputLower.contains("connection")
            || outputLower.contains("timeout")
        {
            AppLogger.shared.log("⚠️ [PackageManager] Network connectivity issue detected")
            AppLogger.shared.log("💡 [PackageManager] Check internet connection and try again")
        }

        if outputLower.contains("formula") && outputLower.contains("not found") {
            AppLogger.shared.log("⚠️ [PackageManager] Formula not found - may need to update Homebrew")
            AppLogger.shared.log("💡 [PackageManager] Suggested fix: brew update")
        }

        if outputLower.contains("disk") || outputLower.contains("space")
            || outputLower.contains("no space left")
        {
            AppLogger.shared.log("⚠️ [PackageManager] Disk space issue detected")
            AppLogger.shared.log("💡 [PackageManager] Free up disk space and try again")
        }

        if exitCode == 1, outputLower.contains("already installed") {
            AppLogger.shared.log(
                "ℹ️ [PackageManager] Package may already be installed but not detected in PATH"
            )
        }
    }

    /// Gets installation recommendations based on current system state
    public func getInstallationRecommendations() async -> [InstallationRecommendation] {
        var recommendations: [InstallationRecommendation] = []

        let kanataInfo = await detectKanataInstallation()

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
                    )
                )
            } else {
                recommendations.append(
                    InstallationRecommendation(
                        package: .kanata,
                        method: .manual,
                        priority: .high,
                        command: "Download from GitHub releases",
                        description: "Install Homebrew first, then install Kanata"
                    )
                )
            }
        }

        // Karabiner-Elements is always required for the VirtualHID driver pipeline
        recommendations.append(
            InstallationRecommendation(
                package: .karabinerElements,
                method: .manual,
                priority: .high,
                command: "Download from https://karabiner-elements.pqrs.org/",
                description: "Install Karabiner-Elements to provide the required VirtualHID driver"
            )
        )

        return recommendations
    }
}

// MARK: - Supporting Types

public enum KanataInstallationType {
    case bundled
    case homebrew
    case cargo
    case manual
    case notInstalled

    public var displayName: String {
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
public enum CodeSigningStatus: Sendable {
    case developerIDSigned(authority: String)
    case adhocSigned
    case unsigned
    case invalid(reason: String)

    public var isDeveloperID: Bool {
        if case .developerIDSigned = self { return true }
        return false
    }

    public var isAdHoc: Bool {
        if case .adhocSigned = self { return true }
        return false
    }
}

public struct KanataInstallationInfo {
    public let isInstalled: Bool
    public let path: String?
    public let installationType: KanataInstallationType
    public let version: String?
    public let codeSigningStatus: CodeSigningStatus

    public var needsReplacement: Bool {
        !codeSigningStatus.isDeveloperID
    }

    public var description: String {
        if isInstalled, let path {
            let versionInfo = version ?? "Unknown version"
            let signing =
                switch codeSigningStatus {
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

public struct PackageManagerInfo {
    public let homebrewAvailable: Bool
    public let homebrewPath: String?
    public let homebrewBinPath: String?
    public let kanataInstallation: KanataInstallationInfo
    public let supportedPackageManagers: [PackageManager.PackageManagerType]

    public var description: String {
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

public enum InstallationMethod {
    case homebrew
    case manual
    case cargo

    public var displayName: String {
        switch self {
        case .homebrew: "Homebrew"
        case .manual: "Manual Download"
        case .cargo: "Cargo (Rust)"
        }
    }
}

public enum InstallationPriority {
    case high
    case medium
    case low

    public var displayName: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }
}

public struct InstallationRecommendation {
    public let package: PackageManager.PackageInfo
    public let method: InstallationMethod
    public let priority: InstallationPriority
    public let command: String
    public let description: String

    public var displayText: String {
        """
        \(package.name) (\(priority.displayName) Priority)
        Method: \(method.displayName)
        Command: \(command)
        Description: \(description)
        """
    }
}
