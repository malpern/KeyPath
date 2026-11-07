import Foundation
import KeyPathRulesCore

public protocol ConfigRepairService: Sendable {
    /// Attempts to repair a broken configuration string using AI
    /// - Parameters:
    ///   - config: The invalid configuration content
    ///   - errors: The validation errors returned by kanata
    ///   - mappings: The intended key mappings
    /// - Returns: A corrected configuration string
    func repairConfig(config: String, errors: [String], mappings: [KeyMapping]) async throws -> String
}
