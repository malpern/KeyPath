import Foundation

// MARK: - Native Layout JSON Format

/// Codable representation of a physical key for JSON serialization.
/// This is the "native" format used by MacBook and other layouts that store
/// pre-computed key geometry directly (as opposed to the QMK format which
/// requires a keyMapping function to resolve keyCodes and labels).
struct PhysicalKeyDTO: Codable {
    let keyCode: UInt16
    let label: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let rotation: Double?
    let rotationPivotX: Double?
    let rotationPivotY: Double?
    let shiftLabel: String?
    let subLabel: String?
    let tertiaryLabel: String?

    func toPhysicalKey() -> PhysicalKey {
        PhysicalKey(
            keyCode: keyCode,
            label: label,
            x: x,
            y: y,
            width: width,
            height: height,
            rotation: rotation ?? 0.0,
            rotationPivotX: rotationPivotX,
            rotationPivotY: rotationPivotY,
            shiftLabel: shiftLabel,
            subLabel: subLabel,
            tertiaryLabel: tertiaryLabel
        )
    }
}

/// Codable representation of a complete physical layout for JSON serialization.
struct PhysicalLayoutDTO: Codable {
    let id: String
    let name: String
    let keys: [PhysicalKeyDTO]
    let totalWidth: Double?
    let totalHeight: Double?

    func toPhysicalLayout() -> PhysicalLayout {
        let physicalKeys = keys.map { $0.toPhysicalKey() }
        if let totalWidth, let totalHeight {
            return PhysicalLayout(
                id: id,
                name: name,
                keys: physicalKeys,
                totalWidth: totalWidth,
                totalHeight: totalHeight
            )
        }
        return PhysicalLayout(
            id: id,
            name: name,
            keys: physicalKeys
        )
    }
}

// MARK: - Loader

/// Loads physical keyboard layouts from native JSON files bundled in the app.
///
/// Native JSON files contain pre-computed key geometry with keyCodes and labels
/// already resolved. This is used for MacBook layouts and other layouts that
/// don't use QMK keyMapping functions.
enum PhysicalLayoutLoader {
    /// Load a native-format layout JSON from the app bundle.
    ///
    /// - Parameters:
    ///   - filename: The JSON filename without extension (e.g., "macbook-us")
    ///   - idOverride: Optional override for the layout ID
    ///   - nameOverride: Optional override for the layout display name
    /// - Returns: A `PhysicalLayout` if loading succeeds, nil otherwise
    static func loadFromBundle(
        filename: String,
        idOverride: String? = nil,
        nameOverride: String? = nil
    ) -> PhysicalLayout? {
        guard let url = KeyPathAppKitResources.url(forResource: filename, withExtension: "json") else {
            print("PhysicalLayoutLoader: Could not find \(filename).json in bundle")
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            print("PhysicalLayoutLoader: Could not read data from \(filename).json")
            return nil
        }
        return load(from: data, idOverride: idOverride, nameOverride: nameOverride)
    }

    /// Parse a native-format layout from JSON data.
    ///
    /// - Parameters:
    ///   - data: The JSON data
    ///   - idOverride: Optional override for the layout ID
    ///   - nameOverride: Optional override for the layout display name
    /// - Returns: A `PhysicalLayout` if parsing succeeds, nil otherwise
    static func load(
        from data: Data,
        idOverride: String? = nil,
        nameOverride: String? = nil
    ) -> PhysicalLayout? {
        guard let dto = try? JSONDecoder().decode(PhysicalLayoutDTO.self, from: data) else {
            print("PhysicalLayoutLoader: Failed to decode layout JSON")
            return nil
        }
        var layout = dto.toPhysicalLayout()
        if let idOverride {
            layout = PhysicalLayout(
                id: idOverride,
                name: nameOverride ?? layout.name,
                keys: layout.keys,
                totalWidth: layout.totalWidth,
                totalHeight: layout.totalHeight
            )
        } else if let nameOverride {
            layout = PhysicalLayout(
                id: layout.id,
                name: nameOverride,
                keys: layout.keys,
                totalWidth: layout.totalWidth,
                totalHeight: layout.totalHeight
            )
        }
        return layout
    }
}

