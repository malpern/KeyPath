import Foundation

@MainActor
final class ConfigurationManager {
    typealias Config = KanataConfiguration

    private let service: ConfigurationService

    init(service: ConfigurationService = ConfigurationService()) {
        self.service = service
    }

    // Read
    func current() async -> Config { await service.current() }
    func reload() async throws -> Config { try await service.reload() }

    // Observe
    @discardableResult
    func observe(_ onChange: @Sendable @escaping (Config) async -> Void) -> ConfigurationObservationToken {
        service.observe(onChange)
    }

    // Save
    func save(keyMappings: [KeyMapping]) async throws { try await service.saveConfiguration(keyMappings: keyMappings) }
    func save(input: String, output: String) async throws { try await service.saveConfiguration(input: input, output: output) }

    // Validate
    func validateTCP() async -> (isValid: Bool, errors: [String])? { await service.validateConfigViaTCP() }
    func validateFile() -> (isValid: Bool, errors: [String]) { service.validateConfigViaFile() }

    // Setup / Repair
    func createInitialConfigIfNeeded() async throws { try await service.createInitialConfigIfNeeded() }
    func backupFailedAndApplySafe(failedConfig: String, mappings: [KeyMapping]) async throws -> String {
        try await service.backupFailedConfigAndApplySafe(failedConfig: failedConfig, mappings: mappings)
    }
    func repair(config: String, errors: [String], mappings: [KeyMapping]) async throws -> String {
        try await service.repairConfiguration(config: config, errors: errors, mappings: mappings)
    }

    // File monitoring
    @discardableResult
    func startMonitoring() -> ConfigurationObservationToken { service.startFileMonitoring() }
}

