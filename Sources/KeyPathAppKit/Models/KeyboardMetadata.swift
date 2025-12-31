import Foundation

/// Metadata for a QMK keyboard, used for search and display
struct KeyboardMetadata: Identifiable, Hashable, Sendable {
    let id: String // Directory name (e.g., "crkbd")
    let name: String // Display name (e.g., "Corne (crkbd)")
    let manufacturer: String? // Manufacturer name (e.g., "foostan")
    let url: URL? // Product page URL
    let maintainer: String? // GitHub username
    let tags: [String] // Inferred tags (split, RGB, ortho, OLED, etc.)
    let infoJsonURL: URL // Raw GitHub URL to info.json

    /// Initialize from QMK keyboard info and directory path
    init(
        id: String,
        name: String,
        manufacturer: String? = nil,
        url: String? = nil,
        maintainer: String? = nil,
        tags: [String] = [],
        infoJsonURL: URL
    ) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.url = url.flatMap { URL(string: $0) }
        self.maintainer = maintainer
        self.tags = tags
        self.infoJsonURL = infoJsonURL
    }

    /// Initialize from QMKKeyboardInfo and directory path
    init(
        directoryName: String,
        info: QMKLayoutParser.QMKKeyboardInfo,
        infoJsonURL: URL
    ) {
        id = directoryName
        name = info.name
        manufacturer = info.manufacturer
        url = info.url.flatMap { URL(string: $0) }
        maintainer = info.maintainer
        tags = info.features?.tags ?? []
        self.infoJsonURL = infoJsonURL
    }
}
