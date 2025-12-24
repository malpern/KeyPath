import Foundation

/// Parser for QMK-style keyboard layout JSON files
/// Format reference: https://docs.qmk.fm/reference_info_json
enum QMKLayoutParser {
    // MARK: - JSON Types

    /// Root structure of a QMK info.json file
    struct QMKKeyboardInfo: Decodable {
        let id: String
        let name: String
        let layouts: [String: QMKLayoutDefinition]
    }

    struct QMKLayoutDefinition: Decodable {
        let layout: [QMKKey]
    }

    struct QMKKey: Decodable {
        let row: Int
        let col: Int
        let x: Double
        let y: Double
        let w: Double? // Width, defaults to 1
        let h: Double? // Height, defaults to 1
        let r: Double? // Rotation in degrees
        let rx: Double? // Rotation pivot X
        let ry: Double? // Rotation pivot Y
        let keyCode: UInt16? // macOS CGEvent key code (optional for backward compatibility)
        let label: String? // Display label (optional for backward compatibility)
    }

    // MARK: - Parsing

    /// Parse a QMK layout JSON file and convert to PhysicalLayout
    /// - Parameters:
    ///   - data: JSON data
    ///   - keyMapping: Function that maps (row, col) matrix position to (keyCode, label)
    ///   - idOverride: Optional ID to use instead of the one in the JSON
    ///   - nameOverride: Optional name to use instead of the one in the JSON
    /// - Returns: PhysicalLayout or nil if parsing fails
    static func parse(
        data: Data,
        keyMapping: (_ row: Int, _ col: Int) -> (keyCode: UInt16, label: String)?,
        idOverride: String? = nil,
        nameOverride: String? = nil
    ) -> PhysicalLayout? {
        do {
            let info = try JSONDecoder().decode(QMKKeyboardInfo.self, from: data)
            guard let defaultLayout = info.layouts["default_transform"] ?? info.layouts.values.first else {
                return nil
            }

            var keys: [PhysicalKey] = []

            for qmkKey in defaultLayout.layout {
                // Prefer keyCode and label from JSON if present (Tier 1 keyboards)
                // Fall back to keyMapping function for backward compatibility (Tier 2/3)
                let (keyCode, label): (UInt16, String)
                if let jsonKeyCode = qmkKey.keyCode, let jsonLabel = qmkKey.label {
                    // JSON has keyCode and label - use them directly
                    keyCode = jsonKeyCode
                    label = jsonLabel
                } else if let mapping = keyMapping(qmkKey.row, qmkKey.col) {
                    // Fall back to keyMapping function
                    keyCode = mapping.keyCode
                    label = mapping.label
                } else {
                    // Skip keys we don't have mappings for
                    continue
                }

                let key = PhysicalKey(
                    keyCode: keyCode,
                    label: label,
                    x: qmkKey.x,
                    y: qmkKey.y,
                    width: qmkKey.w ?? 1.0,
                    height: qmkKey.h ?? 1.0,
                    rotation: qmkKey.r ?? 0.0
                )
                keys.append(key)
            }

            return PhysicalLayout(
                id: idOverride ?? info.id,
                name: nameOverride ?? info.name,
                keys: keys
            )
        } catch {
            print("QMKLayoutParser: Failed to parse JSON: \(error)")
            return nil
        }
    }

    /// Load and parse a QMK layout from the app bundle
    /// - Parameters:
    ///   - filename: Name of the JSON file (without extension)
    ///   - keyMapping: Function that maps (row, col) to (keyCode, label)
    ///   - idOverride: Optional ID to use instead of the one in the JSON
    ///   - nameOverride: Optional name to use instead of the one in the JSON
    /// - Returns: PhysicalLayout or nil if loading fails
    static func loadFromBundle(
        filename: String,
        keyMapping: @escaping (_ row: Int, _ col: Int) -> (keyCode: UInt16, label: String)?,
        idOverride: String? = nil,
        nameOverride: String? = nil
    ) -> PhysicalLayout? {
        guard let url = Bundle.module.url(forResource: filename, withExtension: "json") else {
            print("QMKLayoutParser: Could not find \(filename).json in bundle")
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            print("QMKLayoutParser: Could not read data from \(filename).json")
            return nil
        }
        return parse(data: data, keyMapping: keyMapping, idOverride: idOverride, nameOverride: nameOverride)
    }
}
