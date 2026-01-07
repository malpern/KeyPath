import Foundation
import KeyPathCore

/// Service for importing QMK keyboard layouts from URLs or files
actor QMKImportService {
    static let shared = QMKImportService()

    private init() {}

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
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
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
    private func parseQMKData(_ data: Data, sourceURL: String?, layoutVariant: String?, keyMappingType: KeyMappingType) throws -> PhysicalLayout {
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
        }

        // Generate ID only for new imports (when sourceURL is provided)
        // For reloads from storage, pass nil and let the caller set the ID
        let idOverride: String? = if sourceURL != nil {
            "custom-\(UUID().uuidString)"
        } else {
            nil // Will use JSON's ID or generate in QMKLayoutParser
        }

        // Parse layout using QMKLayoutParser
        guard let layout = QMKLayoutParser.parse(
            data: data,
            keyMapping: keyMapping,
            idOverride: idOverride,
            nameOverride: info.name
        ) else {
            throw QMKImportError.parseError("Failed to parse layout from JSON")
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
    func saveCustomLayout(
        layout: PhysicalLayout,
        name: String,
        sourceURL: String?,
        layoutJSON: Data,
        layoutVariant: String?
    ) {
        var store = CustomLayoutStore.load()

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
            layoutVariant: layoutVariant
        )

        store.layouts.append(storedLayout)
        store.save()

        // Invalidate cache so UI refreshes
        PhysicalLayout.invalidateCustomLayoutCache()
    }

    /// Load all custom layouts from storage
    /// - Returns: Array of PhysicalLayout objects reconstructed from stored data
    func loadCustomLayouts() -> [PhysicalLayout] {
        let store = CustomLayoutStore.load()

        return store.layouts.compactMap { storedLayout in
            // Determine keycode mapping type from variant
            let keyMappingType: KeyMappingType = if let variant = storedLayout.layoutVariant?.lowercased(), variant.contains("iso") {
                .iso
            } else {
                .ansi
            }

            // Re-parse the layout from stored JSON, preserving the stored ID
            do {
                // Pass nil for sourceURL so we can set the ID explicitly
                let layout = try parseQMKData(
                    storedLayout.layoutJSON,
                    sourceURL: nil,
                    layoutVariant: storedLayout.layoutVariant,
                    keyMappingType: keyMappingType
                )
                // Override ID to match stored layout ID
                return PhysicalLayout(
                    id: "custom-\(storedLayout.id)",
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
        var store = CustomLayoutStore.load()
        store.layouts.removeAll { $0.id == layoutId }
        store.save()

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
