import AppKit
import KeyPathCore
import KeyPathRulesCore
import SwiftUI

@Observable
@MainActor
final class LauncherStore {
    var mappings: [LauncherMapping] = []
    private let manager: RuleCollectionsManager?
    var saveError: String?
    private var pendingMutationCount = 0
    var isSaving: Bool { pendingMutationCount > 0 }
    private let ruleCollectionStore: RuleCollectionStore
    private(set) var pendingSave: Task<Void, Never>?

    init(manager: RuleCollectionsManager? = nil) {
        self.manager = manager
        ruleCollectionStore = manager?.ruleCollectionStore ?? .shared
        loadFromRuleCollections()
    }

    /// Testing init that accepts pre-populated mappings without hitting RuleCollectionStore.
    init(testMappings: [LauncherMapping], manager: RuleCollectionsManager? = nil) {
        self.manager = manager
        ruleCollectionStore = manager?.ruleCollectionStore ?? .shared
        mappings = testMappings
    }

    /// Load mappings from the shared RuleCollectionStore (same source as keyboard view)
    func loadFromRuleCollections() {
        Task { @MainActor in
            let collections = await ruleCollectionStore.loadCollections()

            // Find the launcher collection and extract its mappings
            guard let launcherCollection = collections.first(where: { $0.id == RuleCollectionIdentifier.launcher }),
                  let config = launcherCollection.configuration.launcherGridConfig
            else {
                AppLogger.shared.debug("🚀 [LauncherStore] No launcher config found, using defaults")
                mappings = Self.defaultMappings
                return
            }

            // Filter for installed apps (keep all non-app targets)
            let filteredMappings: [LauncherMapping] = config.mappings.filter { mapping in
                switch mapping.action {
                case let .launchApp(name, bundleId):
                    Self.isAppInstalled(name: name, bundleId: bundleId)
                case .openURL, .openFolder, .runScript:
                    true
                default:
                    true
                }
            }

            mappings = filteredMappings
            AppLogger.shared.info("🚀 [LauncherStore] Loaded \(mappings.count) launcher mappings")
        }
    }

    func reloadFromCollections() {
        loadFromRuleCollections()
    }

    /// Mappings sorted by proximity to the physical home row.
    var sortedMappings: [LauncherMapping] {
        mappings.sorted { Self.homeRowProximity(for: $0.key) < Self.homeRowProximity(for: $1.key) }
    }

    /// Home row proximity score (lower = closer to home row)
    private static func homeRowProximity(for key: String) -> Int {
        let normalized = normalizeCanonicalKey(key)
        return rowPriorityByCanonicalKey[normalized] ?? 4
    }

    private static let rowPriorityByCanonicalKey: [String: Int] = {
        let rows: [(priority: Int, keyCodes: [UInt16])] = [
            (0, [0, 1, 2, 3, 5, 4, 38, 40, 37, 41]), // home row
            (1, [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30]), // top row + brackets
            (2, [6, 7, 8, 9, 11, 45, 46, 43, 47, 44]), // bottom row + punctuation
            (3, [18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24, 50]) // number row + grave
        ]

        var map: [String: Int] = [:]
        for row in rows {
            for keyCode in row.keyCodes {
                let canonical = OverlayKeyboardView.keyCodeToKanataName(keyCode).lowercased()
                map[canonical] = row.priority
            }
        }
        return map
    }()

    private static func normalizeCanonicalKey(_ key: String) -> String {
        let normalized = key.lowercased()
        let aliases: [String: String] = [
            ";": "semicolon",
            "'": "apostrophe",
            ",": "comma",
            ".": "dot",
            "/": "slash",
            "-": "minus",
            "=": "equal",
            "`": "grave",
            "[": "leftbrace",
            "]": "rightbrace",
            "\\": "backslash"
        ]
        return aliases[normalized] ?? normalized
    }

    /// Check if an app is installed on the system
    private static func isAppInstalled(name: String, bundleId: String?) -> Bool {
        // Try bundle ID first (most reliable)
        if let bundleId, NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil {
            return true
        }

        // Fall back to app name in common locations
        let paths = [
            "/Applications/\(name).app",
            "/System/Applications/\(name).app",
            "/System/Applications/Utilities/\(name).app",
            "/Applications/Utilities/\(name).app"
        ]

        for path in paths {
            if Foundation.FileManager().fileExists(atPath: path) {
                return true
            }
        }

        return false
    }

    func addMapping(_ mapping: LauncherMapping) {
        enqueueMutation { config in
            if let index = config.mappings.firstIndex(where: { $0.id == mapping.id }) {
                config.mappings[index] = mapping
            } else {
                config.mappings.append(mapping)
            }
        }
    }

    func updateMapping(_ mapping: LauncherMapping) {
        enqueueMutation { config in
            if let index = config.mappings.firstIndex(where: { $0.id == mapping.id }) {
                config.mappings[index] = mapping
            }
        }
    }

    func deleteMapping(_ id: UUID) {
        enqueueMutation { $0.mappings.removeAll { $0.id == id } }
    }

    private static var defaultMappings: [LauncherMapping] {
        [
            LauncherMapping(key: "s", action: .launchApp(name: "Safari", bundleId: nil)),
            LauncherMapping(key: "t", action: .launchApp(name: "Terminal", bundleId: nil)),
            LauncherMapping(key: "f", action: .launchApp(name: "Finder", bundleId: nil)),
            LauncherMapping(key: "g", action: .openURL("github.com"))
        ]
    }

    /// Get icon for an app - checks multiple locations
    static func appIcon(name: String, bundleId: String?) -> NSImage? {
        AppIconResolver.icon(for: .launchApp(name: name, bundleId: bundleId))
    }

    /// Merge each edit into the latest committed state after acquiring the
    /// configuration lease. Never publish JSON ahead of its generated config.
    private func enqueueMutation(
        _ edit: @escaping @MainActor @Sendable (inout LauncherGridConfig) -> Void
    ) {
        let previous = pendingSave
        pendingMutationCount += 1
        pendingSave = Task { @MainActor in
            await previous?.value
            defer { pendingMutationCount -= 1 }
            guard let manager else {
                saveError = "The shortcut could not be saved. Reopen the launcher and try again."
                return
            }
            let saved = await manager.editLauncherConfiguration(edit)
            saveError = saved ? nil : "The shortcut could not be saved. Your previous shortcuts were kept."
            if let config = manager.ruleCollections.first(where: { $0.id == RuleCollectionIdentifier.launcher })?.configuration.launcherGridConfig {
                mappings = config.mappings.filter { mapping in
                    if case let .launchApp(name, bundleId) = mapping.action {
                        return Self.isAppInstalled(name: name, bundleId: bundleId)
                    }
                    return true
                }
            }
        }
    }
}
