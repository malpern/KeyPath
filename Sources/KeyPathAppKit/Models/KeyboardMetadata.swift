import Foundation

/// Metadata for a QMK keyboard, used for search and display
struct KeyboardMetadata: Identifiable, Hashable, Sendable {
    let id: String // QMK path (e.g., "crkbd/rev1", "mode/m65s")
    let name: String // Display name (e.g., "Corne (crkbd)")
    let manufacturer: String? // Manufacturer name (e.g., "foostan")
    let url: URL? // Product page URL
    let maintainer: String? // GitHub username
    let tags: [String] // Inferred tags (split, RGB, ortho, OLED, etc.)
    let infoJsonURL: URL? // QMK API URL to info.json (nil for custom/local layouts)
    let isBundled: Bool // Whether this keyboard has full layout data in popular-keyboards.json
    let builtInLayoutId: String? // If set, this QMK keyboard has a built-in PhysicalLayout equivalent

    /// Initialize with all fields
    init(
        id: String,
        name: String,
        manufacturer: String? = nil,
        url: String? = nil,
        maintainer: String? = nil,
        tags: [String] = [],
        infoJsonURL: URL? = nil,
        isBundled: Bool = false,
        builtInLayoutId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.url = url.flatMap { URL(string: $0) }
        self.maintainer = maintainer
        self.tags = tags
        self.infoJsonURL = infoJsonURL
        self.isBundled = isBundled
        self.builtInLayoutId = builtInLayoutId
    }

    /// Initialize from QMKKeyboardInfo and directory path
    init(
        directoryName: String,
        info: QMKLayoutParser.QMKKeyboardInfo,
        infoJsonURL: URL? = nil
    ) {
        id = directoryName
        name = info.name
        manufacturer = info.manufacturer
        url = info.url.flatMap { URL(string: $0) }
        maintainer = info.maintainer
        tags = info.features?.tags ?? []
        self.infoJsonURL = infoJsonURL
        isBundled = false
        builtInLayoutId = nil
    }
}
