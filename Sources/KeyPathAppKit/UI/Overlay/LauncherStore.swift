import AppKit
import KeyPathCore
import SwiftUI

@Observable
@MainActor
final class LauncherStore {
    var mappings: [QuickLaunchMapping] = []
    private var knownMappingIds: Set<UUID> = []

    init() {
        loadFromRuleCollections()
    }

    /// Testing init that accepts pre-populated mappings without hitting RuleCollectionStore.
    init(testMappings: [QuickLaunchMapping]) {
        mappings = testMappings
        knownMappingIds = Set(testMappings.map(\.id))
    }

    /// Load mappings from the shared RuleCollectionStore (same source as keyboard view)
    func loadFromRuleCollections() {
        Task { @MainActor in
            let collections = await RuleCollectionStore.shared.loadCollections()

            // Find the launcher collection and extract its mappings
            guard let launcherCollection = collections.first(where: { $0.id == RuleCollectionIdentifier.launcher }),
                  let config = launcherCollection.configuration.launcherGridConfig
            else {
                AppLogger.shared.debug("🚀 [LauncherStore] No launcher config found, using defaults")
                mappings = Self.defaultMappings
                return
            }

            // Convert LauncherMapping to QuickLaunchMapping, filtering for installed apps
            let convertedMappings: [QuickLaunchMapping] = config.mappings.compactMap { mapping in
                guard mapping.isEnabled else { return nil }

                switch mapping.target {
                case let .app(name, bundleId):
                    // Check if app is installed
                    guard Self.isAppInstalled(name: name, bundleId: bundleId) else { return nil }
                    return QuickLaunchMapping(
                        id: mapping.id,
                        key: mapping.key,
                        targetType: .app,
                        targetName: name,
                        bundleId: bundleId,
                        isEnabled: mapping.isEnabled
                    )
                case let .url(urlString):
                    return QuickLaunchMapping(
                        id: mapping.id,
                        key: mapping.key,
                        targetType: .website,
                        targetName: urlString,
                        bundleId: nil,
                        isEnabled: mapping.isEnabled
                    )
                case .folder, .script:
                    // Skip folders and scripts for now
                    return nil
                }
            }

            mappings = convertedMappings
            knownMappingIds = Set(convertedMappings.map(\.id))
            AppLogger.shared.info("🚀 [LauncherStore] Loaded \(mappings.count) launcher mappings")
        }
    }

    /// Mappings sorted by proximity to the physical home row.
    var sortedMappings: [QuickLaunchMapping] {
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
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }

        return false
    }

    func addMapping(_ mapping: QuickLaunchMapping) {
        mappings.append(mapping)
        persistMappings()
    }

    func updateMapping(_ mapping: QuickLaunchMapping) {
        if let index = mappings.firstIndex(where: { $0.id == mapping.id }) {
            mappings[index] = mapping
        }
        persistMappings()
    }

    func deleteMapping(_ id: UUID) {
        mappings.removeAll { $0.id == id }
        persistMappings()
    }

    private static var defaultMappings: [QuickLaunchMapping] {
        [
            QuickLaunchMapping(key: "s", targetType: .app, targetName: "Safari"),
            QuickLaunchMapping(key: "t", targetType: .app, targetName: "Terminal"),
            QuickLaunchMapping(key: "f", targetType: .app, targetName: "Finder"),
            QuickLaunchMapping(key: "g", targetType: .website, targetName: "github.com")
        ]
    }

    /// Get icon for an app - checks multiple locations
    static func appIcon(name: String, bundleId: String?) -> NSImage? {
        AppIconResolver.icon(for: .app(name: name, bundleId: bundleId))
    }

    private func persistMappings() {
        let currentMappings = mappings
        let removedIds = knownMappingIds.subtracting(currentMappings.map(\.id))

        Task { @MainActor in
            var collections = await RuleCollectionStore.shared.loadCollections()
            guard let index = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.launcher }) else {
                return
            }
            var collection = collections[index]
            guard var config = collection.configuration.launcherGridConfig else { return }

            var updatedMappings = config.mappings
            updatedMappings.removeAll { removedIds.contains($0.id) }

            for quick in currentMappings {
                let target: LauncherTarget = switch quick.targetType {
                case .app:
                    .app(name: quick.targetName, bundleId: quick.bundleId)
                case .website:
                    .url(quick.targetName)
                }

                if let existingIndex = updatedMappings.firstIndex(where: { $0.id == quick.id }) {
                    updatedMappings[existingIndex].key = quick.key
                    updatedMappings[existingIndex].target = target
                    updatedMappings[existingIndex].isEnabled = quick.isEnabled
                } else {
                    updatedMappings.append(LauncherMapping(
                        id: quick.id,
                        key: quick.key,
                        target: target,
                        isEnabled: quick.isEnabled
                    ))
                }
            }

            config.mappings = updatedMappings
            collection.configuration = .launcherGrid(config)
            collections[index] = collection
            try? await RuleCollectionStore.shared.saveCollections(collections)
            NotificationCenter.default.post(name: .ruleCollectionsChanged, object: nil)

            knownMappingIds = Set(currentMappings.map(\.id))
        }
    }
}
