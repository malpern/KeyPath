import Foundation
import KeyPathCore

/// Parser for QMK-style keyboard layout JSON files
/// Format reference: https://docs.qmk.fm/reference_info_json
enum QMKLayoutParser {
    // MARK: - JSON Types

    /// Root structure of a QMK info.json file
    struct QMKKeyboardInfo: Decodable {
        let id: String
        let name: String
        let layouts: [String: QMKLayoutDefinition]

        // Metadata fields (optional for backward compatibility)
        let manufacturer: String?
        let url: String?
        let maintainer: String?
        let features: QMKFeatures?

        /// Custom coding keys to handle missing fields
        enum CodingKeys: String, CodingKey {
            case id
            case name
            case keyboard_name // QMK uses keyboard_name, but we map to name
            case layouts
            case manufacturer
            case url
            case maintainer
            case features
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            // Handle id (may not exist in real QMK JSON, derive from context)
            if let idValue = try? container.decode(String.self, forKey: .id) {
                id = idValue
            } else {
                // Fallback: use keyboard_name or generate
                id = (try? container.decode(String.self, forKey: .keyboard_name)) ?? "unknown"
            }

            // Handle name (QMK uses keyboard_name, but our bundled JSON uses name)
            if let nameValue = try? container.decode(String.self, forKey: .name) {
                name = nameValue
            } else if let keyboardName = try? container.decode(String.self, forKey: .keyboard_name) {
                name = keyboardName
            } else {
                name = id // Fallback to id
            }

            layouts = try container.decode([String: QMKLayoutDefinition].self, forKey: .layouts)
            manufacturer = try? container.decode(String.self, forKey: .manufacturer)
            url = try? container.decode(String.self, forKey: .url)
            maintainer = try? container.decode(String.self, forKey: .maintainer)
            features = try? container.decode(QMKFeatures.self, forKey: .features)
        }
    }

    /// QMK features object (for extracting tags)
    struct QMKFeatures: Decodable {
        let bootmagic: Bool?
        let extrakey: Bool?
        let nkro: Bool?
        let oled: Bool?
        let rgblight: Bool?
        let rgb_matrix: Bool?

        /// Split keyboard support
        let split: QMKSplit?

        /// Extract tags from features
        var tags: [String] {
            var result: [String] = []
            if split?.enabled == true {
                result.append("split")
            }
            if rgb_matrix == true || rgblight == true {
                result.append("RGB")
            }
            if oled == true {
                result.append("OLED")
            }
            return result
        }
    }

    /// QMK split keyboard configuration
    struct QMKSplit: Decodable {
        let enabled: Bool?
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

        // Multi-legend support (JIS/ISO keyboards)
        let shiftLabel: String? // Shifted character (top position)
        let subLabel: String? // Alternate input legend (front/bottom-right, e.g., hiragana)
        let tertiaryLabel: String? // Additional legend (front/bottom-left)

        enum CodingKeys: String, CodingKey {
            case row, col, x, y, w, h, r, rx, ry
            case keyCode, label, shiftLabel, subLabel, tertiaryLabel
            case matrix // QMK API uses "matrix": [row, col] instead of separate row/col
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            x = try container.decode(Double.self, forKey: .x)
            y = try container.decode(Double.self, forKey: .y)
            w = try container.decodeIfPresent(Double.self, forKey: .w)
            h = try container.decodeIfPresent(Double.self, forKey: .h)
            r = try container.decodeIfPresent(Double.self, forKey: .r)
            rx = try container.decodeIfPresent(Double.self, forKey: .rx)
            ry = try container.decodeIfPresent(Double.self, forKey: .ry)
            keyCode = try container.decodeIfPresent(UInt16.self, forKey: .keyCode)
            label = try container.decodeIfPresent(String.self, forKey: .label)
            shiftLabel = try container.decodeIfPresent(String.self, forKey: .shiftLabel)
            subLabel = try container.decodeIfPresent(String.self, forKey: .subLabel)
            tertiaryLabel = try container.decodeIfPresent(String.self, forKey: .tertiaryLabel)

            // Handle row/col: either direct fields or from "matrix": [row, col]
            if let r = try container.decodeIfPresent(Int.self, forKey: .row),
               let c = try container.decodeIfPresent(Int.self, forKey: .col)
            {
                row = r
                col = c
            } else if let matrix = try container.decodeIfPresent([Int].self, forKey: .matrix),
                      matrix.count >= 2
            {
                row = matrix[0]
                col = matrix[1]
            } else {
                row = 0
                col = 0
            }
        }
    }

    // MARK: - Validation Constants

    /// Period for rotation normalization (degrees); output is clamped to ±180°
    static let rotationNormalizationPeriod: Double = 360.0

    /// Minimum allowed key size (prevents zero-size or negative-size keys)
    static let minimumKeySize: Double = 0.1

    /// Maximum allowed key size (sanity check for malformed data)
    static let maximumKeySize: Double = 20.0

    /// Maximum allowed coordinate value (sanity check)
    static let maximumCoordinate: Double = 100.0

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

                // Skip keys with zero or negative or NaN/Inf size
                let rawWidth = qmkKey.w ?? 1.0
                let rawHeight = qmkKey.h ?? 1.0
                if rawWidth <= 0 || rawHeight <= 0 || rawWidth.isNaN || rawHeight.isNaN
                    || rawWidth.isInfinite || rawHeight.isInfinite
                {
                    continue
                }

                // Clamp key dimensions to valid range
                let width = clampKeySize(rawWidth)
                let height = clampKeySize(rawHeight)

                // Clamp rotation to valid range
                let rotation = clampRotation(qmkKey.r ?? 0.0)

                // Validate coordinates (skip keys with absurd positions)
                guard abs(qmkKey.x) <= maximumCoordinate, abs(qmkKey.y) <= maximumCoordinate else {
                    continue
                }

                // Use empty string for missing labels rather than crashing
                let safeLabel = label.isEmpty ? "?" : label

                let key = PhysicalKey(
                    keyCode: keyCode,
                    label: safeLabel,
                    x: qmkKey.x,
                    y: qmkKey.y,
                    width: width,
                    height: height,
                    rotation: rotation,
                    rotationPivotX: qmkKey.rx,
                    rotationPivotY: qmkKey.ry,
                    shiftLabel: qmkKey.shiftLabel,
                    subLabel: qmkKey.subLabel,
                    tertiaryLabel: qmkKey.tertiaryLabel
                )
                keys.append(key)
            }

            // Reject layouts with 0 valid keys
            guard !keys.isEmpty else {
                return nil
            }

            return PhysicalLayout(
                id: idOverride ?? info.id,
                name: nameOverride ?? info.name,
                keys: keys
            )
        } catch {
            AppLogger.shared.error("⚠️ [QMKLayoutParser] Failed to parse JSON: \(error)")
            return nil
        }
    }

    /// Parse a QMK layout using row-based ordering to infer keyCodes.
    /// Groups keys by row, sorts left-to-right, assigns keyCodes by position.
    /// This works for any standard staggered QMK keyboard regardless of matrix wiring.
    static func parseByPosition(
        data: Data,
        idOverride: String? = nil,
        nameOverride: String? = nil
    ) -> PhysicalLayout? {
        guard let result = parseByPositionWithQuality(data: data, idOverride: idOverride, nameOverride: nameOverride) else {
            return nil
        }
        return result.layout
    }

    /// Parse a QMK layout using default keymap data for key identity.
    /// This is the standard approach used by QMK Configurator, VIA, and all other tools:
    /// keymapTokens[i] tells us what layoutArray[i] does.
    ///
    /// - Parameters:
    ///   - data: JSON data from QMK API (info.json format)
    ///   - keymapTokens: Base layer keycode names in layout order (from keymap.c/json)
    ///   - idOverride: Optional ID override
    ///   - nameOverride: Optional name override
    /// - Returns: ParseResult with high match ratio, or nil if parsing fails
    static func parseWithKeymap(
        data: Data,
        keymapTokens: [String],
        idOverride: String? = nil,
        nameOverride: String? = nil
    ) -> ParseResult? {
        do {
            let info = try JSONDecoder().decode(QMKKeyboardInfo.self, from: data)
            guard let defaultLayout = info.layouts["default_transform"] ?? info.layouts.values.first else {
                return nil
            }

            // Collect valid keys
            var validKeys: [(qmkKey: QMKKey, index: Int)] = []
            for (i, qmkKey) in defaultLayout.layout.enumerated() {
                let rawWidth = qmkKey.w ?? 1.0
                let rawHeight = qmkKey.h ?? 1.0
                if rawWidth <= 0 || rawHeight <= 0 || rawWidth.isNaN || rawHeight.isNaN
                    || rawWidth.isInfinite || rawHeight.isInfinite
                { continue }
                guard abs(qmkKey.x) <= maximumCoordinate, abs(qmkKey.y) <= maximumCoordinate else { continue }
                validKeys.append((qmkKey, i))
            }
            guard !validKeys.isEmpty else { return nil }

            // Map keys using original QMK layout index for token lookup.
            // entry.index is the key's position in the raw QMK layout array, which
            // corresponds 1:1 with keymapTokens. Using entry.index (not the enumerated
            // idx) ensures correct alignment when keys are filtered from validKeys.
            var keys: [PhysicalKey] = []
            var matchedCount = 0

            for entry in validKeys {
                let qmkKey = entry.qmkKey
                let originalIdx = entry.index
                let keyCode: UInt16
                let label: String

                // First: check if key has JSON-embedded keyCode (bundled keyboards)
                if let jsonKeyCode = qmkKey.keyCode, let jsonLabel = qmkKey.label {
                    keyCode = jsonKeyCode
                    label = jsonLabel
                    matchedCount += 1
                }
                // Second: use keymap token at this index
                else if originalIdx < keymapTokens.count,
                        let resolved = QMKKeymapParser.resolveKeycode(keymapTokens[originalIdx])
                {
                    keyCode = resolved.keyCode
                    label = resolved.label
                    matchedCount += 1
                }
                // Third: token exists but is a layer/transparent key — render the key but with a layer indicator
                else if originalIdx < keymapTokens.count {
                    let token = keymapTokens[originalIdx]
                    if token == "_______" || token == "KC_TRNS" || token == "KC_TRANSPARENT" {
                        keyCode = PhysicalKey.unmappedKeyCode
                        label = ""
                        matchedCount += 1 // Transparent is a valid assignment
                    } else if token == "KC_NO" || token == "XXXXXXX" {
                        keyCode = PhysicalKey.unmappedKeyCode
                        label = ""
                        matchedCount += 1
                    } else {
                        // Layer key, macro, etc. — show abbreviated label
                        keyCode = PhysicalKey.unmappedKeyCode
                        label = abbreviateToken(token)
                        matchedCount += 1
                    }
                }
                // Fallback: no keymap data for this position
                else {
                    keyCode = PhysicalKey.placeholderKeyCode(for: originalIdx)
                    label = "?"
                }

                keys.append(PhysicalKey(
                    keyCode: keyCode, label: label.isEmpty ? "" : label,
                    x: qmkKey.x, y: qmkKey.y,
                    width: clampKeySize(qmkKey.w ?? 1.0), height: clampKeySize(qmkKey.h ?? 1.0),
                    rotation: clampRotation(qmkKey.r ?? 0.0),
                    rotationPivotX: qmkKey.rx, rotationPivotY: qmkKey.ry,
                    shiftLabel: qmkKey.shiftLabel, subLabel: qmkKey.subLabel,
                    tertiaryLabel: qmkKey.tertiaryLabel
                ))
            }

            let totalKeys = keys.count
            let unmatchedKeys = keys.filter { $0.label == "?" }.count
            let matchRatio = Double(totalKeys - unmatchedKeys) / Double(totalKeys)

            return ParseResult(
                layout: PhysicalLayout(id: idOverride ?? info.id, name: nameOverride ?? info.name, keys: keys),
                matchRatio: matchRatio, totalKeys: totalKeys, unmatchedKeys: unmatchedKeys
            )
        } catch {
            AppLogger.shared.error("⚠️ [QMKLayoutParser] Failed to parse JSON: \(error)")
            return nil
        }
    }

    /// Abbreviate a compound keycode token for display (e.g., "MO(1)" → "L1", "LT(2, KC_SPC)" → "L2")
    static func abbreviateToken(_ token: String) -> String {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("MO(") {
            let num = String(t.dropFirst(3).dropLast()).trimmingCharacters(in: .whitespaces)
            return "L\(num)"
        }
        if t.hasPrefix("TG(") {
            let num = String(t.dropFirst(3).dropLast()).trimmingCharacters(in: .whitespaces)
            return "T\(num)"
        }
        if t.hasPrefix("LT(") {
            let num = String(t.dropFirst(3).prefix(while: { $0 != "," })).trimmingCharacters(in: .whitespaces)
            return "L\(num)"
        }
        if t.hasPrefix("OSL(") {
            let num = String(t.dropFirst(4).dropLast()).trimmingCharacters(in: .whitespaces)
            return "L\(num)"
        }
        if t.hasPrefix("DF(") {
            let num = String(t.dropFirst(3).dropLast()).trimmingCharacters(in: .whitespaces)
            return "D\(num)"
        }
        if t.hasPrefix("QK_BOOT") { return "⟲" }
        if t.hasPrefix("RGB_") { return "RGB" }
        if t.hasPrefix("BL_") { return "BL" }
        // Generic: first 3 chars
        return String(t.prefix(3))
    }

    /// Result of position-based parsing, includes match quality info
    struct ParseResult {
        let layout: PhysicalLayout
        /// Fraction of keys that matched a known position (0.0–1.0)
        let matchRatio: Double
        let totalKeys: Int
        let unmatchedKeys: Int

        var isHighQuality: Bool {
            matchRatio >= 0.9
        }

        var isUsable: Bool {
            matchRatio >= 0.5
        }
    }

    /// Parse with full result including match quality metrics.
    /// Uses row-based ordering: groups keys by y into rows, sorts left-to-right,
    /// assigns keyCodes by position index using ANSI templates.
    static func parseByPositionWithQuality(
        data: Data,
        idOverride: String? = nil,
        nameOverride: String? = nil
    ) -> ParseResult? {
        do {
            let info = try JSONDecoder().decode(QMKKeyboardInfo.self, from: data)
            guard let defaultLayout = info.layouts["default_transform"] ?? info.layouts.values.first else {
                return nil
            }

            // Step 1: Collect valid keys and their positions
            var validKeys: [(qmkKey: QMKKey, index: Int)] = []
            for (i, qmkKey) in defaultLayout.layout.enumerated() {
                let rawWidth = qmkKey.w ?? 1.0
                let rawHeight = qmkKey.h ?? 1.0
                if rawWidth <= 0 || rawHeight <= 0 || rawWidth.isNaN || rawHeight.isNaN
                    || rawWidth.isInfinite || rawHeight.isInfinite
                { continue }
                guard abs(qmkKey.x) <= maximumCoordinate, abs(qmkKey.y) <= maximumCoordinate else { continue }
                validKeys.append((qmkKey, i))
            }
            guard !validKeys.isEmpty else { return nil }

            // Step 2: Separate keys that have JSON-provided keyCodes from those needing mapping
            var jsonMappedKeys: [(qmkKey: QMKKey, index: Int)] = []
            var positionKeys: [ANSIPositionTable.QMKKeyPosition] = []

            for (qmkKey, idx) in validKeys {
                if qmkKey.keyCode != nil, qmkKey.label != nil {
                    jsonMappedKeys.append((qmkKey, idx))
                } else {
                    positionKeys.append(ANSIPositionTable.QMKKeyPosition(
                        x: qmkKey.x, y: qmkKey.y,
                        width: qmkKey.w ?? 1.0, index: idx
                    ))
                }
            }

            // Step 3: Run row-based mapping on keys that need it
            let rowMappings = ANSIPositionTable.mapKeysByRow(qmkKeys: positionKeys)
            let mappingDict = Dictionary(uniqueKeysWithValues: rowMappings.map { ($0.index, $0) })

            // Step 4: Build PhysicalKey array
            var keys: [PhysicalKey] = []
            for (qmkKey, idx) in validKeys {
                let keyCode: UInt16
                let label: String

                if let jsonKeyCode = qmkKey.keyCode, let jsonLabel = qmkKey.label {
                    keyCode = jsonKeyCode
                    label = jsonLabel
                } else if let mapping = mappingDict[idx] {
                    keyCode = mapping.keyCode
                    label = mapping.label
                } else {
                    keyCode = PhysicalKey.placeholderKeyCode(for: idx)
                    label = "?"
                }

                keys.append(PhysicalKey(
                    keyCode: keyCode, label: label.isEmpty ? "?" : label,
                    x: qmkKey.x, y: qmkKey.y,
                    width: clampKeySize(qmkKey.w ?? 1.0), height: clampKeySize(qmkKey.h ?? 1.0),
                    rotation: clampRotation(qmkKey.r ?? 0.0),
                    rotationPivotX: qmkKey.rx, rotationPivotY: qmkKey.ry,
                    shiftLabel: qmkKey.shiftLabel, subLabel: qmkKey.subLabel,
                    tertiaryLabel: qmkKey.tertiaryLabel
                ))
            }

            let totalKeys = keys.count
            let unmatchedKeys = keys.filter { $0.label == "?" }.count
            let matchRatio = Double(totalKeys - unmatchedKeys) / Double(totalKeys)

            return ParseResult(
                layout: PhysicalLayout(id: idOverride ?? info.id, name: nameOverride ?? info.name, keys: keys),
                matchRatio: matchRatio, totalKeys: totalKeys, unmatchedKeys: unmatchedKeys
            )
        } catch {
            AppLogger.shared.error("⚠️ [QMKLayoutParser] Failed to parse JSON: \(error)")
            return nil
        }
    }

    // MARK: - Validation Helpers

    /// Clamp key size to valid range
    static func clampKeySize(_ size: Double) -> Double {
        if size <= 0 || size.isNaN {
            return minimumKeySize
        }
        return min(size, maximumKeySize)
    }

    /// Normalize rotation to the -180°...180° range
    static func clampRotation(_ degrees: Double) -> Double {
        if degrees.isNaN || degrees.isInfinite {
            return 0.0
        }
        var normalized = degrees.truncatingRemainder(dividingBy: rotationNormalizationPeriod)
        if normalized > rotationNormalizationPeriod / 2 {
            normalized -= rotationNormalizationPeriod
        } else if normalized < -rotationNormalizationPeriod / 2 {
            normalized += rotationNormalizationPeriod
        }
        return normalized
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
        guard let url = KeyPathAppKitResources.url(forResource: filename, withExtension: "json") else {
            AppLogger.shared.error("⚠️ [QMKLayoutParser] Could not find \(filename).json in bundle")
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            AppLogger.shared.error("⚠️ [QMKLayoutParser] Could not read data from \(filename).json")
            return nil
        }
        return parse(data: data, keyMapping: keyMapping, idOverride: idOverride, nameOverride: nameOverride)
    }
}
