import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import XCTest

/// Parser/write tests use only an explicitly supplied or worktree-local bridge.
/// No installed-app fallback and no production validation bypass.
enum SessionBridgeTestFixture {
    static var libraryPath: String {
        ProcessInfo.processInfo.environment["KEYPATH_SESSION_TEST_BRIDGE_PATH"]
            ?? URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/kanata-host-bridge/libkeypath_kanata_host_bridge.dylib").path
    }

    static var runtimeHost: KanataRuntimeHost {
        KanataRuntimeHost(
            launcherPath: "/unused/kanata-launcher", bridgeLibraryPath: libraryPath,
            bundledCorePath: "/unused/kanata", kanataEngineBundlePath: "/unused/Kanata Engine.app"
        )
    }

    /// The capability profile the fixture's bridge gives. Tests that compare
    /// `isSupportedInDriverlessSession` with a fixture admission install this as
    /// `BackendCapabilityProfile.testOverride`, since `.shared` asks whatever
    /// bridge the host process finds (an installed app's, possibly older).
    static var profile: BackendCapabilityProfile {
        BackendCapabilityProfile(backend: .session) { key in
            KanataHostBridge.sessionOutputKeySupported(
                runtimeHost: runtimeHost, keyName: key, supportedUsages: SessionKeyMap.sessionOutputUsages
            )
        }
    }

    static func requireAvailable() throws {
        guard FileManager.default.fileExists(atPath: libraryPath) else {
            if ProcessInfo.processInfo.environment["KEYPATH_SESSION_TEST_BRIDGE_PATH"] != nil {
                throw NSError(domain: "SessionBridgeTestFixture", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Explicit session bridge is missing: \(libraryPath)"])
            }
            throw XCTSkip("Bridge-dependent test needs a fresh local bridge or KEYPATH_SESSION_TEST_BRIDGE_PATH")
        }
    }
}

extension ConfigurationService {
    @MainActor
    static func sessionTestService(
        configDirectory: String,
        ruleCollectionStore: RuleCollectionStore? = nil,
        customRulesStore: CustomRulesStore? = nil,
        deviceSelectionStore: DeviceSelectionStore = .shared,
        synchronizePreferences: @escaping @Sendable (RecoverableRuleWrite.PreferenceDefaults) -> Bool = { $0.value.synchronize() }
    ) -> ConfigurationService {
        let directory = URL(fileURLWithPath: configDirectory)
        return ConfigurationService(
            configDirectory: configDirectory,
            ruleCollectionStore: ruleCollectionStore ?? .testStore(at: directory.appendingPathComponent("RuleCollections.json")),
            customRulesStore: customRulesStore ?? .testStore(at: directory.appendingPathComponent("CustomRules.json")),
            deviceSelectionStore: deviceSelectionStore,
            sessionValidationRuntimeHost: SessionBridgeTestFixture.runtimeHost,
            synchronizePreferences: synchronizePreferences
        )
    }
}
