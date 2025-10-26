import Foundation

@MainActor
extension KanataManager {
    // MARK: - Kanata Arguments Builder

    /// Builds Kanata command line arguments including TCP port when enabled
    func buildKanataArguments(configPath: String, checkOnly: Bool = false) -> [String] {
        var arguments = ["--cfg", configPath]

        // Add TCP communication arguments if enabled
        let commConfig = PreferencesService.communicationSnapshot()
        if commConfig.shouldUseTCP {
            arguments.append(contentsOf: commConfig.communicationLaunchArguments)
            AppLogger.shared.log("📡 [KanataArgs] TCP server enabled on port \(commConfig.tcpPort)")
        } else {
            AppLogger.shared.log("📡 [KanataArgs] TCP server disabled")
        }

        if checkOnly {
            arguments.append("--check")
        } else {
            // Note: --watch removed - we use TCP reload commands for config changes
            arguments.append("--debug")
            arguments.append("--log-layer-changes")
        }

        AppLogger.shared.log("🔧 [KanataArgs] Built arguments: \(arguments.joined(separator: " "))")
        return arguments
    }
}

