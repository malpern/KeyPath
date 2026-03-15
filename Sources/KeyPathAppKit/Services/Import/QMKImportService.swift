import Foundation
import KeyPathCore

/// Service for importing QMK keyboard layouts from URLs or files
actor QMKImportService {
    static let shared = QMKImportService()
    private let userDefaultsSuiteName: String?

    init(userDefaultsSuiteName: String? = nil) {
        self.userDefaultsSuiteName = userDefaultsSuiteName
    }

    private var userDefaults: UserDefaults {
        guard let userDefaultsSuiteName else { return .standard }
        return UserDefaults(suiteName: userDefaultsSuiteName) ?? .standard
    }

    /// Import a QMK layout from a URL
    /// - Parameters:
    ///   - url: URL to the QMK info.json file (typically GitHub raw URL)
    ///   - layoutVariant: Optional layout variant name (e.g., "ansi", "iso"). If nil, uses "default_transform" or first available
    ///   - keyMappingType: Type of keycode mapping to use (ansi or iso)
    /// - Returns: Parsed PhysicalLayout
    /// - Throws: QMKImportError
    func importFromURL(_ url: URL, layoutVariant: String? = nil, keyMappingType: KeyMappingType = .ansi) async throws -> PhysicalLayout {
        // Validate URL
        guard url.scheme == "https" || url.scheme == "http" else {
            throw QMKImportError.invalidURL("URL must use http or https protocol")
        }

        // Fetch JSON data
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QMKImportError.networkError("Invalid response type")
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw QMKImportError.networkError("HTTP \(httpResponse.statusCode): \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))")
        }

        // Check response size (10MB limit)
        if data.count > 10 * 1024 * 1024 {
            throw QMKImportError.invalidJSON("Response too large (max 10MB). Size: \(data.count / 1024 / 1024)MB")
        }

        return try parseQMKData(data, sourceURL: url.absoluteString, layoutVariant: layoutVariant, keyMappingType: keyMappingType)
    }

    /// Import a QMK layout from a local file
    /// - Parameters:
    ///   - fileURL: Local file URL to the QMK info.json file
    ///   - layoutVariant: Optional layout variant name
    ///   - keyMappingType: Type of keycode mapping to use
    /// - Returns: Parsed PhysicalLayout
    /// - Throws: QMKImportError
    func importFromFile(_ fileURL: URL, layoutVariant: String? = nil, keyMappingType: KeyMappingType = .ansi) async throws -> PhysicalLayout {
        guard fileURL.isFileURL else {
            throw QMKImportError.invalidURL("File URL must be a local file path")
        }

        // Check file size before reading (10MB limit)
        let fileAttributes = try Foundation.FileManager().attributesOfItem(atPath: fileURL.path)
        if let fileSize = fileAttributes[.size] as? Int64, fileSize > 10 * 1024 * 1024 {
            throw QMKImportError.invalidJSON("File too large (max 10MB). File size: \(fileSize / 1024 / 1024)MB")
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw QMKImportError.invalidURL("Failed to read file: \(error.localizedDescription)")
        }

        // Double-check data size (in case attributes check failed)
        if data.count > 10 * 1024 * 1024 {
            throw QMKImportError.invalidJSON("File too large (max 10MB). File size: \(data.count / 1024 / 1024)MB")
        }

        return try parseQMKData(data, sourceURL: nil, layoutVariant: layoutVariant, keyMappingType: keyMappingType)
    }

    /// Parse QMK JSON data and convert to PhysicalLayout
    /// - Parameter idOverride: If nil, QMKLayoutParser will generate an ID from the JSON
    private func parseQMKData(_ data: Data, sourceURL: String?, layoutVariant _: String?, keyMappingType: KeyMappingType) throws -> PhysicalLayout {
        // Decode QMK keyboard info
        let info: QMKLayoutParser.QMKKeyboardInfo
        do {
            info = try JSONDecoder().decode(QMKLayoutParser.QMKKeyboardInfo.self, from: data)
        } catch {
            throw QMKImportError.invalidJSON("Failed to parse JSON: \(error.localizedDescription)")
        }

        guard !info.layouts.isEmpty else {
            throw QMKImportError.noLayoutFound("No layout definitions found in JSON")
        }

        // Choose keycode mapping function based on type
        let keyMapping: (Int, Int) -> (keyCode: UInt16, label: String)? = switch keyMappingType {
        case .ansi:
            ANSIPositionTable.keyMapping(row:col:)
        case .iso:
            ISOPositionTable.keyMapping(row:col:)
        case .jis:
            JISPositionTable.keyMapping(row:col:)
        }

        // Generate ID only for new imports (when sourceURL is provided)
        // For reloads from storage, pass nil and let the caller set the ID
        let idOverride: String? = if sourceURL != nil {
            "custom-\(UUID().uuidString)"
        } else {
            nil // Will use JSON's ID or generate in QMKLayoutParser
        }

        // Use a safe name: fall back to "Imported Keyboard" if name is empty
        let safeName = info.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Imported Keyboard"
            : info.name

        // Parse layout using QMKLayoutParser
        guard let layout = QMKLayoutParser.parse(
            data: data,
            keyMapping: keyMapping,
            idOverride: idOverride,
            nameOverride: safeName
        ) else {
            throw QMKImportError.parseError("Failed to parse layout from JSON. The layout may have 0 valid keys.")
        }

        return layout
    }

    /// Save a custom layout to persistent storage
    /// - Parameters:
    ///   - layout: The PhysicalLayout to save
    ///   - name: User-provided name for the layout (will be made unique if duplicate)
    ///   - sourceURL: Original import URL (if any)
    ///   - layoutJSON: Raw JSON data used to create the layout
    ///   - layoutVariant: Selected layout variant name
    ///   - keyboardPath: QMK keyboard path for re-fetching keymap
    func saveCustomLayout(
        layout: PhysicalLayout,
        name: String,
        sourceURL: String?,
        layoutJSON: Data,
        layoutVariant: String?,
        defaultKeymap: [String]? = nil,
        keyboardPath: String? = nil
    ) {
        var store = CustomLayoutStore.load(from: userDefaults)

        // Ensure unique name
        let existingNames = Set(store.layouts.map(\.name))
        var uniqueName = name
        if existingNames.contains(uniqueName) {
            var counter = 2
            while existingNames.contains(uniqueName) {
                uniqueName = "\(name) (\(counter))"
                counter += 1
            }
        }

        // Use layout's ID if it starts with "custom-", otherwise generate new UUID
        let layoutId = layout.id.hasPrefix("custom-") ? String(layout.id.dropFirst(7)) : UUID().uuidString

        let storedLayout = StoredLayout(
            id: layoutId,
            name: uniqueName,
            sourceURL: sourceURL,
            layoutJSON: layoutJSON,
            layoutVariant: layoutVariant,
            defaultKeymap: defaultKeymap,
            keyboardPath: keyboardPath
        )

        store.layouts.append(storedLayout)
        store.save(to: userDefaults)

        // Invalidate cache so UI refreshes
        PhysicalLayout.invalidateCustomLayoutCache()
    }

    /// Replace any existing QMK-imported layout with a new one (at most 1 QMK import at a time).
    /// Removes all existing QMK imports (those with a sourceURL containing "keyboards.qmk.fm"),
    /// then saves the new one.
    func replaceQMKImport(
        layout: PhysicalLayout,
        name: String,
        sourceURL: String?,
        layoutJSON: Data,
        layoutVariant: String?,
        defaultKeymap: [String]? = nil,
        keyboardPath: String? = nil
    ) {
        var store = CustomLayoutStore.load(from: userDefaults)

        // Remove existing QMK imports
        store.layouts.removeAll { stored in
            stored.sourceURL?.contains("keyboards.qmk.fm") == true
        }
        store.save(to: userDefaults)

        // Save the new one
        saveCustomLayout(
            layout: layout,
            name: name,
            sourceURL: sourceURL,
            layoutJSON: layoutJSON,
            layoutVariant: layoutVariant,
            defaultKeymap: defaultKeymap,
            keyboardPath: keyboardPath
        )
    }

    /// Check if a stored layout has a keyboard path (needed for keymap re-fetch).
    func hasKeyboardPath(layoutId: String) -> Bool {
        let store = CustomLayoutStore.load(from: userDefaults)
        return store.layouts.first { $0.id == layoutId }?.keyboardPath != nil
    }

    /// Result of a keymap refresh attempt
    enum KeymapRefreshResult {
        case success(tokenCount: Int)
        case failure(String)
    }

    /// Re-fetch the keymap for a stored layout and update it in place.
    func refreshKeymap(layoutId: String) async -> KeymapRefreshResult {
        var store = CustomLayoutStore.load(from: userDefaults)

        guard let index = store.layouts.firstIndex(where: { $0.id == layoutId }) else {
            return .failure("Layout not found")
        }

        let storedLayout = store.layouts[index]

        guard let kbPath = storedLayout.keyboardPath else {
            return .failure("No keyboard path available for re-fetch")
        }

        // Invalidate the cached keymap to force a fresh fetch
        await QMKKeyboardDatabase.shared.invalidateKeymapCache(keyboardPath: kbPath)

        // Attempt to fetch the keymap
        guard let keymapTokens = await QMKKeyboardDatabase.shared.fetchDefaultKeymap(keyboardPath: kbPath) else {
            return .failure("Could not fetch keymap — GitHub may be rate-limited or the keymap is unavailable for this keyboard")
        }

        // Update the stored layout with the new keymap tokens
        let updated = StoredLayout(
            id: storedLayout.id,
            name: storedLayout.name,
            sourceURL: storedLayout.sourceURL,
            layoutJSON: storedLayout.layoutJSON,
            importDate: storedLayout.importDate,
            layoutVariant: storedLayout.layoutVariant,
            defaultKeymap: keymapTokens,
            keyboardPath: storedLayout.keyboardPath
        )

        store.layouts[index] = updated
        store.save(to: userDefaults)

        // Invalidate cache so UI refreshes with new labels
        PhysicalLayout.invalidateCustomLayoutCache()

        return .success(tokenCount: keymapTokens.count)
    }

    /// Load all custom layouts from storage
    /// - Returns: Array of PhysicalLayout objects reconstructed from stored data
    func loadCustomLayouts() -> [PhysicalLayout] {
        var store = CustomLayoutStore.load(from: userDefaults)

        // Deduplicate QMK imports: keep only the most recent one
        let qmkImports = store.layouts.filter { $0.sourceURL?.contains("keyboards.qmk.fm") == true }
        if qmkImports.count > 1 {
            let newest = qmkImports.max(by: { $0.importDate < $1.importDate })
            store.layouts.removeAll { stored in
                stored.sourceURL?.contains("keyboards.qmk.fm") == true && stored.id != newest?.id
            }
            store.save(to: userDefaults)
        }

        return store.layouts.compactMap { storedLayout in
            // Determine keycode mapping type from variant
            let keyMappingType: KeyMappingType = if let variant = storedLayout.layoutVariant?.lowercased() {
                if variant.contains("jis") || variant.contains("jp") {
                    .jis
                } else if variant.contains("iso") {
                    .iso
                } else {
                    .ansi
                }
            } else {
                .ansi
            }

            // Re-parse the layout from stored JSON, preserving the stored ID
            do {
                let layoutId = "custom-\(storedLayout.id)"

                // Strategy 1: Use cached keymap tokens (best quality)
                if let keymapTokens = storedLayout.defaultKeymap,
                   let result = QMKLayoutParser.parseWithKeymap(
                       data: storedLayout.layoutJSON,
                       keymapTokens: keymapTokens,
                       idOverride: layoutId,
                       nameOverride: storedLayout.name
                   )
                {
                    return result.layout
                }

                // Strategy 2: Position-based parsing (works regardless of matrix wiring)
                if let result = QMKLayoutParser.parseByPositionWithQuality(
                    data: storedLayout.layoutJSON,
                    idOverride: layoutId,
                    nameOverride: storedLayout.name
                ) {
                    return result.layout
                }

                // Strategy 3: Matrix-based parsing for bundled keyboards with known matrices
                let layout = try parseQMKData(
                    storedLayout.layoutJSON,
                    sourceURL: nil,
                    layoutVariant: storedLayout.layoutVariant,
                    keyMappingType: keyMappingType
                )
                return PhysicalLayout(
                    id: layoutId,
                    name: storedLayout.name,
                    keys: layout.keys
                )
            } catch {
                AppLogger.shared.warn("⚠️ [QMKImportService] Failed to reload custom layout '\(storedLayout.name)': \(error.localizedDescription)")
                return nil
            }
        }
    }

    /// Delete a custom layout
    /// - Parameter layoutId: ID of the layout to delete
    func deleteCustomLayout(layoutId: String) {
        var store = CustomLayoutStore.load(from: userDefaults)
        store.layouts.removeAll { $0.id == layoutId }
        store.save(to: userDefaults)

        // Invalidate cache so UI refreshes
        PhysicalLayout.invalidateCustomLayoutCache()
    }

    /// Get available layout variants from a QMK JSON
    /// - Parameter data: QMK JSON data
    /// - Returns: Array of layout variant names
    /// - Throws: QMKImportError
    /// Note: This is a nonisolated method since it only reads data, no shared state
    nonisolated func getAvailableVariants(from data: Data) throws -> [String] {
        let info: QMKLayoutParser.QMKKeyboardInfo
        do {
            info = try JSONDecoder().decode(QMKLayoutParser.QMKKeyboardInfo.self, from: data)
        } catch {
            throw QMKImportError.invalidJSON("Failed to parse JSON: \(error.localizedDescription)")
        }
        return Array(info.layouts.keys).sorted()
    }
}

/// Type of keycode mapping to use when parsing QMK layouts
enum KeyMappingType {
    case ansi
    case iso
    case jis
}

/// Errors that can occur during QMK import
enum QMKImportError: LocalizedError {
    case invalidURL(String)
    case networkError(String)
    case invalidJSON(String)
    case noLayoutFound(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case let .invalidURL(message):
            "Invalid URL: \(message)"
        case let .networkError(message):
            "Network error: \(message)"
        case let .invalidJSON(message):
            "Invalid JSON: \(message)"
        case let .noLayoutFound(message):
            "No layout found: \(message)"
        case let .parseError(message):
            "Parse error: \(message)"
        }
    }
}
