import Foundation
import KeyPathPermissions
import SwiftUI

// MARK: - Permission Snapshot Provider DI

/// Minimal protocol to provide permission snapshots from the Oracle
protocol PermissionSnapshotProviding {
    func currentSnapshot() async -> PermissionOracle.Snapshot
}

extension PermissionOracle: PermissionSnapshotProviding {}

// Adapter to avoid storing actor singletons directly in nonisolated defaults
private struct PermissionOracleAdapter: PermissionSnapshotProviding, Sendable {
    func currentSnapshot() async -> PermissionOracle.Snapshot {
        await PermissionOracle.shared.currentSnapshot()
    }
}

/// EnvironmentKey for injecting a permission snapshot provider
@preconcurrency private struct PermissionSnapshotProviderKey: EnvironmentKey {
    static var defaultValue: PermissionSnapshotProviding { PermissionOracleAdapter() }
}

extension EnvironmentValues {
    var permissionSnapshotProvider: PermissionSnapshotProviding {
        get { self[PermissionSnapshotProviderKey.self] }
        set { self[PermissionSnapshotProviderKey.self] = newValue }
    }
}

// MARK: - Preferences Service DI

/// EnvironmentKey for PreferencesService (DI)
@preconcurrency private struct PreferencesServiceKey: EnvironmentKey {
    static var defaultValue: PreferencesService { PreferencesService() }
}

extension EnvironmentValues {
    var preferencesService: PreferencesService {
        get { self[PreferencesServiceKey.self] }
        set { self[PreferencesServiceKey.self] = newValue }
    }
}

// MARK: - Privileged Operations DI

/// EnvironmentKey for PrivilegedOperations (DI)
@preconcurrency private struct PrivilegedOperationsKey: EnvironmentKey {
    static var defaultValue: PrivilegedOperations { LegacyPrivilegedOperations() }
}

extension EnvironmentValues {
    var privilegedOperations: PrivilegedOperations {
        get { self[PrivilegedOperationsKey.self] }
        set { self[PrivilegedOperationsKey.self] = newValue }
    }
}
