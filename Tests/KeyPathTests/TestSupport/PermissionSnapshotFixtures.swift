import Foundation
@testable import KeyPathPermissions

extension PermissionOracle.Snapshot {
    /// A snapshot with KeyPath's Accessibility grant and the runtime's key-access report.
    static func fixture(
        accessibility: PermissionOracle.Status = .granted,
        runtimeKeyAccess: PermissionOracle.Status = .granted,
        source: String = "test",
        timestamp: Date = Date()
    ) -> PermissionOracle.Snapshot {
        PermissionOracle.Snapshot(
            accessibility: accessibility,
            runtimeKeyAccess: .init(
                status: runtimeKeyAccess, source: source,
                confidence: runtimeKeyAccess == .unknown ? .low : .high, timestamp: timestamp
            ),
            timestamp: timestamp
        )
    }
}
