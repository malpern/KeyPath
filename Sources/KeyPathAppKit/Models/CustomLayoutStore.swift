import Foundation
import KeyPathCore

/// Storage model for custom imported keyboard layouts
struct CustomLayoutStore: Codable {
    var layouts: [StoredLayout]

    static let userDefaultsKey = "customKeyboardLayouts"

    /// Load custom layouts from UserDefaults
    static func load() -> CustomLayoutStore {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let store = try? JSONDecoder().decode(CustomLayoutStore.self, from: data)
        else {
            return CustomLayoutStore(layouts: [])
        }
        return store
    }

    /// Save custom layouts to UserDefaults
    func save() {
        guard let data = try? JSONEncoder().encode(self) else {
            AppLogger.shared.error("🔧 [CustomLayoutStore] Failed to encode custom layouts")
            return
        }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }
}

/// A single stored custom layout
struct StoredLayout: Codable, Identifiable {
    let id: String // UUID
    let name: String // User-provided name
    let sourceURL: String? // Original import URL
    let layoutJSON: Data // Raw QMK JSON for re-parsing
    let importDate: Date
    let layoutVariant: String? // Selected layout variant (e.g., "ansi", "iso")

    init(id: String = UUID().uuidString,
         name: String,
         sourceURL: String? = nil,
         layoutJSON: Data,
         importDate: Date = Date(),
         layoutVariant: String? = nil)
    {
        self.id = id
        self.name = name
        self.sourceURL = sourceURL
        self.layoutJSON = layoutJSON
        self.importDate = importDate
        self.layoutVariant = layoutVariant
    }
}
