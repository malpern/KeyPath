import Foundation
import KeyPathPermissions
import SwiftUI

// MARK: - Permission Snapshot Provider DI

/// Minimal protocol to provide permission snapshots from the Oracle
protocol PermissionSnapshotProviding: Sendable {
    func currentSnapshot() async -> PermissionOracle.Snapshot
}

extension PermissionOracle: PermissionSnapshotProviding {}

/// Adapter to avoid storing actor singletons directly in nonisolated defaults
private struct PermissionOracleAdapter: PermissionSnapshotProviding {
    func currentSnapshot() async -> PermissionOracle.Snapshot {
        await PermissionOracle.shared.currentSnapshot()
    }
}

/// EnvironmentKey for injecting a permission snapshot provider
private struct PermissionSnapshotProviderKey: EnvironmentKey {
    static var defaultValue: any PermissionSnapshotProviding {
        PermissionOracleAdapter()
    }
}

extension EnvironmentValues {
    var permissionSnapshotProvider: any PermissionSnapshotProviding {
        get { self[PermissionSnapshotProviderKey.self] }
        set { self[PermissionSnapshotProviderKey.self] = newValue }
    }
}

// MARK: - Preferences Service DI

/// EnvironmentKey for PreferencesService (DI)
private struct PreferencesServiceKey: EnvironmentKey {
    static var defaultValue: PreferencesService {
        PreferencesService()
    }
}

extension EnvironmentValues {
    var preferencesService: PreferencesService {
        get { self[PreferencesServiceKey.self] }
        set { self[PreferencesServiceKey.self] = newValue }
    }
}

// MARK: - Service Container DI

/// EnvironmentKey for the central ServiceContainer
private struct ServiceContainerKey: EnvironmentKey {
    // The default is only used as a fallback if .environment(\.services, ...) is missing.
    // In production, the container is always injected from App.init().
    @MainActor static let _default = ServiceContainer()
    nonisolated(unsafe) static var defaultValue: ServiceContainer {
        MainActor.assumeIsolated { _default }
    }
}

extension EnvironmentValues {
    var services: ServiceContainer {
        get { self[ServiceContainerKey.self] }
        set { self[ServiceContainerKey.self] = newValue }
    }
}

