import Foundation
import KeyPathCore

// MARK: - Notifications

public extension Notification.Name {
    /// Posted when app keymaps are added, updated, or removed
    static let appKeymapsDidChange = Notification.Name("appKeymapsDidChange")
    /// Posted when user should navigate to App Rules tab in drawer
    static let switchToAppRulesTab = Notification.Name("switchToAppRulesTab")
    /// Posted when Mapper should open the app condition picker (for "New Rule" from App Rules tab)
    static let openMapperAppConditionPicker = Notification.Name("openMapperAppConditionPicker")
    /// Posted when overlay should open with mapper tab selected (from Settings)
    static let openOverlayWithMapper = Notification.Name("openOverlayWithMapper")
    /// Posted when overlay view should switch to mapper tab
    static let switchToMapperTab = Notification.Name("switchToMapperTab")
    /// Posted when overlay should open with mapper tab and preset values for editing
    /// UserInfo: inputKey (String), outputKey (String), optionally appBundleId (String)
    static let openOverlayWithMapperPreset = Notification.Name("openOverlayWithMapperPreset")
    /// Posted to set the app condition on the mapper (for adding a rule to a specific app)
    /// UserInfo: bundleId (String), displayName (String)
    static let mapperSetAppCondition = Notification.Name("mapperSetAppCondition")
}

/// Persists app-specific keymaps to disk.
///
/// File location: `~/.config/keypath/AppKeymaps.json`
///
/// See ADR-027 for the full architecture.
actor AppKeymapStore {
    static let shared = AppKeymapStore()

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileURL: URL
    private let fileManager: FileManager

    /// In-memory cache of keymaps
    private var cachedKeymaps: [AppKeymap]?

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let defaultDirectory = URL(
            fileURLWithPath: WizardSystemPaths.userConfigDirectory, isDirectory: true
        )
        self.fileURL = fileURL ?? defaultDirectory.appendingPathComponent("AppKeymaps.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: - CRUD Operations

    /// Load all app keymaps from disk
    func loadKeymaps() -> [AppKeymap] {
        if let cached = cachedKeymaps {
            return cached
        }

        AppLogger.shared.log("📂 [AppKeymapStore] loadKeymaps from: \(fileURL.path)")
        guard fileManager.fileExists(atPath: fileURL.path) else {
            AppLogger.shared.log("📂 [AppKeymapStore] File does not exist, returning []")
            cachedKeymaps = []
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            AppLogger.shared.log("📂 [AppKeymapStore] Read \(data.count) bytes from file")
            let keymaps = try decoder.decode([AppKeymap].self, from: data)
            AppLogger.shared.log("📂 [AppKeymapStore] Decoded \(keymaps.count) app keymaps")
            for keymap in keymaps {
                AppLogger.shared.log(
                    "📂 [AppKeymapStore]   - \(keymap.mapping.displayName) (\(keymap.mapping.bundleIdentifier)): \(keymap.overrides.count) overrides"
                )
            }
            cachedKeymaps = keymaps
            return keymaps
        } catch {
            AppLogger.shared.log("⚠️ [AppKeymapStore] Failed to load keymaps: \(error)")
            cachedKeymaps = []
            return []
        }
    }

    /// Save all app keymaps to disk
    func saveKeymaps(_ keymaps: [AppKeymap]) throws {
        AppLogger.shared.log("💾 [AppKeymapStore] saveKeymaps: \(keymaps.count) keymaps to \(fileURL.path)")

        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try encoder.encode(keymaps)
        try data.write(to: fileURL, options: .atomic)
        cachedKeymaps = keymaps

        AppLogger.shared.log("💾 [AppKeymapStore] Saved \(data.count) bytes")
    }

    /// Add or update an app keymap
    func upsertKeymap(_ keymap: AppKeymap) throws {
        var keymaps = loadKeymaps()

        if let index = keymaps.firstIndex(where: { $0.mapping.bundleIdentifier == keymap.mapping.bundleIdentifier }) {
            keymaps[index] = keymap
            AppLogger.shared.log("📝 [AppKeymapStore] Updated keymap for \(keymap.mapping.displayName)")
        } else {
            // Check for virtual key name collision
            let existingNames = Set(keymaps.map(\.mapping.virtualKeyName))
            var finalKeymap = keymap
            if existingNames.contains(keymap.mapping.virtualKeyName) {
                let uniqueName = AppKeyMapping.generateUniqueVirtualKeyName(
                    displayName: keymap.mapping.displayName,
                    bundleIdentifier: keymap.mapping.bundleIdentifier
                )
                finalKeymap = AppKeymap(
                    id: keymap.id,
                    mapping: AppKeyMapping(
                        id: keymap.mapping.id,
                        bundleIdentifier: keymap.mapping.bundleIdentifier,
                        displayName: keymap.mapping.displayName,
                        virtualKeyName: uniqueName,
                        createdAt: keymap.mapping.createdAt,
                        modifiedAt: Date(),
                        isEnabled: keymap.mapping.isEnabled
                    ),
                    overrides: keymap.overrides
                )
                AppLogger.shared.log(
                    "⚠️ [AppKeymapStore] VK name collision, using unique name: \(uniqueName)"
                )
            }
            keymaps.append(finalKeymap)
            AppLogger.shared.log("➕ [AppKeymapStore] Added keymap for \(finalKeymap.mapping.displayName)")
        }

        try saveKeymaps(keymaps)
        postChangeNotification()
    }

    /// Remove an app keymap by bundle identifier
    func removeKeymap(bundleIdentifier: String) throws {
        var keymaps = loadKeymaps()
        let countBefore = keymaps.count
        keymaps.removeAll { $0.mapping.bundleIdentifier == bundleIdentifier }

        if keymaps.count < countBefore {
            try saveKeymaps(keymaps)
            AppLogger.shared.log("🗑️ [AppKeymapStore] Removed keymap for \(bundleIdentifier)")
            postChangeNotification()
        }
    }

    /// Post notification on main thread that keymaps have changed
    private func postChangeNotification() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .appKeymapsDidChange, object: nil)
        }
    }

    /// Get keymap for a specific bundle identifier
    func getKeymap(bundleIdentifier: String) -> AppKeymap? {
        loadKeymaps().first { $0.mapping.bundleIdentifier == bundleIdentifier }
    }

    /// Get all enabled keymaps
    func getEnabledKeymaps() -> [AppKeymap] {
        loadKeymaps().filter(\.mapping.isEnabled)
    }

    /// Get mapping from bundle ID to virtual key name for enabled apps
    func getBundleToVKMapping() -> [String: String] {
        var result: [String: String] = [:]
        for keymap in getEnabledKeymaps() {
            result[keymap.mapping.bundleIdentifier] = keymap.mapping.virtualKeyName
        }
        return result
    }

    /// Invalidate the cache (call after external modifications)
    func invalidateCache() {
        cachedKeymaps = nil
    }
}

// MARK: - Test Support

#if DEBUG
    extension AppKeymapStore {
        nonisolated static func testStore(at url: URL) -> AppKeymapStore {
            AppKeymapStore(fileURL: url)
        }
    }
#endif
