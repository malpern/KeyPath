import Foundation

@MainActor
final class KanataCoordinator {
    private let processService: ProcessService
    private let configManager: ConfigurationManager

    init(processService: ProcessService = ProcessService(),
         configManager: ConfigurationManager = ConfigurationManager()) {
        self.processService = processService
        self.configManager = configManager
    }

    // Orchestration only — delegate to services
    func start() async {
        await processService.cleanupOrphansIfNeeded()
        _ = await processService.startLaunchDaemonService()
    }

    func stop() async {
        _ = await processService.stopLaunchDaemonService()
        await processService.unregisterProcess()
    }

    func restart() async {
        await stop()
        try? await Task.sleep(nanoseconds: 400_000_000)
        await start()
    }

    func reloadConfiguration(keyMappings: [KeyMapping]) async {
        do {
            try await configManager.save(keyMappings: keyMappings)
            // Optionally ping Kanata over TCP if enabled
            // Best-effort: leave actual TCP reload to existing flow
        } catch {
            AppLogger.shared.log("❌ [Coordinator] Failed to save/reload config: \(error)")
        }
    }
}
