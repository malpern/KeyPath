import Foundation

public protocol ConfigRepairService: Sendable {
    /// Attempts to repair a broken configuration string using AI
    /// - Parameters:
    ///   - config: The invalid configuration content
    ///   - errors: The validation errors returned by kanata
    ///   - mappings: The intended key mappings
    /// - Returns: A corrected configuration string
    func repairConfig(config: String, errors: [String], mappings: [KeyMapping]) async throws -> String
}

/// Mock implementation for tests or when AI is disabled
public struct MockConfigRepairService: ConfigRepairService {
    public init() {}

    public func repairConfig(config: String, errors _: [String], mappings _: [KeyMapping]) async throws -> String {
        // Just return the original config to simulate inability to repair without AI
        config
    }
}
