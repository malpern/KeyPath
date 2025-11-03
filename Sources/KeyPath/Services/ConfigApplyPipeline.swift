import Foundation
import KeyPathCore

/// Actor that centralizes config apply flow (validate → write → validate → reload → health).
/// This initial version mirrors legacy behavior and is gated by FeatureFlags.useConfigApplyPipeline.
actor ConfigApplyPipeline {
    private let configPath: String
    private weak var kanataManager: KanataManager?

    init(configPath: String, kanataManager: KanataManager?) {
        self.configPath = configPath
        self.kanataManager = kanataManager
    }

    /// Apply already-generated effective config text.
    func applyEffectiveConfig(_ content: String) async -> ApplyResult {
        // Pre-write validation (in-memory)
        let configService = ConfigurationService(configDirectory: (configPath as NSString).deletingLastPathComponent)
        let pre = await configService.validateConfiguration(content)
        if !pre.isValid {
            let details = pre.errors.joined(separator: "\n")
            return ApplyResult(
                success: false,
                rolledBack: false,
                error: .preWriteValidationFailed(message: "Pre-write validation failed"),
                diagnostics: ConfigDiagnostics(
                    configPathBefore: configPath,
                    validationOutput: details
                )
            )
        }

        // Snapshot original for rollback
        let originalContent: String? = {
            if FileManager.default.fileExists(atPath: configPath) {
                return try? String(contentsOfFile: configPath, encoding: .utf8)
            }
            return nil
        }()

        // Write file atomically (same-directory replace)
        do {
            let directoryURL = URL(fileURLWithPath: (configPath as NSString).deletingLastPathComponent)
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let tempURL = directoryURL.appendingPathComponent(".keypath.tmp.\(UUID().uuidString).kbd")
            let targetURL = URL(fileURLWithPath: configPath)
            try content.write(to: tempURL, atomically: true, encoding: .utf8)
            var resultURL: NSURL?
            try FileManager.default.replaceItemAt(
                targetURL,
                withItemAt: tempURL,
                backupItemName: ".keypath.atomic.bak",
                options: [.usingNewMetadataOnly],
                resultingItemURL: &resultURL
            )
        } catch {
            return ApplyResult(
                success: false,
                rolledBack: false,
                error: .writeFailed(message: error.localizedDescription),
                diagnostics: ConfigDiagnostics(configPathBefore: configPath)
            )
        }

        // Post-write CLI validation
        if let manager = kanataManager {
            let post = await manager.validateConfigFile()
            if !post.isValid {
                // Roll back
                if let original = originalContent {
                    _ = try? original.write(toFile: configPath, atomically: true, encoding: .utf8)
                }
                let details = post.errors.joined(separator: "\n")
                return ApplyResult(
                    success: false,
                    rolledBack: true,
                    error: .postWriteValidationFailed(message: "Post-write CLI validation failed"),
                    diagnostics: ConfigDiagnostics(
                        configPathBefore: configPath,
                        configPathAfter: configPath,
                        validationOutput: details
                    )
                )
            }
        }

        // Reload and readiness/health check
        if let manager = kanataManager {
            _ = await manager.triggerConfigReload()
            manager.clearDiagnostics()
            let ready = await KanataReadinessWatcher.waitForDriverConnected(timeoutSeconds: 2.5)
            if !ready {
                // Roll back
                if let original = originalContent {
                    _ = try? original.write(toFile: configPath, atomically: true, encoding: .utf8)
                }
                return ApplyResult(
                    success: false,
                    rolledBack: true,
                    error: .readinessTimeout(message: "Timeout waiting for driver_connected 1"),
                    diagnostics: ConfigDiagnostics(configPathBefore: configPath, configPathAfter: configPath)
                )
            }
        }

        return ApplyResult(success: true)
    }
}


