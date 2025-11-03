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
        let t0 = Date()
        var pre: (isValid: Bool, errors: [String]) = (true, [])
        if let manager = kanataManager {
            pre = await manager.configurationManager.validateConfiguration(content)
        }
        let preMs = Date().timeIntervalSince(t0) * 1000.0
        if !pre.isValid {
            let details = pre.errors.joined(separator: "\n")
            return ApplyResult(
                success: false,
                rolledBack: false,
                error: .preWriteValidationFailed(message: "Pre-write validation failed"),
                diagnostics: ConfigDiagnostics(
                    configPathBefore: configPath,
                    validationOutput: details,
                    preValidationMs: preMs
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

        // Write file atomically via ConfigurationManager
        do {
            if let manager = kanataManager {
                try manager.configurationManager.writeConfigAtomically(content)
            } else {
                // Fallback to direct atomic replace if manager is unavailable
                let directoryURL = URL(fileURLWithPath: (configPath as NSString).deletingLastPathComponent)
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                let tempURL = directoryURL.appendingPathComponent(".keypath.tmp.\(UUID().uuidString).kbd")
                let targetURL = URL(fileURLWithPath: configPath)
                try content.write(to: tempURL, atomically: true, encoding: .utf8)
                let _ = try FileManager.default.replaceItemAt(
                    targetURL,
                    withItemAt: tempURL,
                    backupItemName: ".keypath.atomic.bak",
                    options: [.usingNewMetadataOnly]
                )
            }
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
            let t1 = Date()
            let post = await manager.validateConfigFile()
            let postMs = Date().timeIntervalSince(t1) * 1000.0
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
                        validationOutput: details,
                        postValidationMs: postMs
                    )
                )
            }
        }

        // Reload and readiness/health check
        if let manager = kanataManager {
            _ = await manager.triggerConfigReload()
            await manager.clearDiagnostics()
            let t2 = Date()
            let ready = await KanataReadinessWatcher.waitForDriverConnected(timeoutSeconds: 2.5)
            let readyMs = Date().timeIntervalSince(t2) * 1000.0
            if !ready {
                // Roll back
                if let original = originalContent {
                    _ = try? original.write(toFile: configPath, atomically: true, encoding: .utf8)
                }
                return ApplyResult(
                    success: false,
                    rolledBack: true,
                    error: .readinessTimeout(message: "Timeout waiting for driver_connected 1"),
                    diagnostics: ConfigDiagnostics(
                        configPathBefore: configPath,
                        configPathAfter: configPath,
                        readinessWaitMs: readyMs
                    )
                )
            }
        }

        return ApplyResult(success: true)
    }
}


