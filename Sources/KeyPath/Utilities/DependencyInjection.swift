import Foundation
import SwiftUI

// MARK: - Permission Snapshot Provider DI

/// Minimal protocol to provide permission snapshots from the Oracle
protocol PermissionSnapshotProviding {
    func currentSnapshot() async -> PermissionOracle.Snapshot
}

extension PermissionOracle: PermissionSnapshotProviding {}

/// EnvironmentKey for injecting a permission snapshot provider
private struct PermissionSnapshotProviderKey: EnvironmentKey {
    static var defaultValue: PermissionSnapshotProviding = PermissionOracle.shared
}

extension EnvironmentValues {
    var permissionSnapshotProvider: PermissionSnapshotProviding {
        get { self[PermissionSnapshotProviderKey.self] }
        set { self[PermissionSnapshotProviderKey.self] = newValue }
    }
}

// MARK: - Preferences Service DI

/// EnvironmentKey for PreferencesService (DI)
private struct PreferencesServiceKey: EnvironmentKey {
    static var defaultValue: PreferencesService = .shared
}

extension EnvironmentValues {
    var preferencesService: PreferencesService {
        get { self[PreferencesServiceKey.self] }
        set { self[PreferencesServiceKey.self] = newValue }
    }
}
