import Foundation
import KeyPathCore

/// Persists user-accepted device → layout bindings.
///
/// When a user accepts an auto-detected keyboard layout, the binding is saved here.
/// On subsequent plug-ins of the same device, the layout switches automatically.
/// File: `~/.config/keypath/DeviceLayoutBindings.json`
actor DeviceLayoutBindingStore {
    static let shared = DeviceLayoutBindingStore()

    struct Binding: Codable, Sendable {
        let vendorProductKey: String // "4653:0001"
        let layoutId: String
        let keyboardName: String
        var acceptedAt: Date
    }

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = Foundation.FileManager()
    ) {
        self.fileManager = fileManager
        let defaultDirectory = URL(
            fileURLWithPath: WizardSystemPaths.userConfigDirectory, isDirectory: true
        )
        self.fileURL = fileURL ?? defaultDirectory.appendingPathComponent("DeviceLayoutBindings.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: - Read

    func binding(vendorID: Int, productID: Int) -> Binding? {
        let key = String(format: "%04X:%04X", vendorID, productID)
        return loadBindings().first { $0.vendorProductKey == key }
    }

    func allBindings() -> [Binding] {
        loadBindings()
    }

    // MARK: - Write

    func saveBinding(_ binding: Binding) throws {
        var bindings = loadBindings()
        bindings.removeAll { $0.vendorProductKey == binding.vendorProductKey }
        bindings.append(binding)
        try persist(bindings)
        AppLogger.shared.log("💾 [DeviceLayoutBindingStore] Saved binding: \(binding.keyboardName) → \(binding.layoutId)")
    }

    func removeBinding(vendorID: Int, productID: Int) throws {
        let key = String(format: "%04X:%04X", vendorID, productID)
        var bindings = loadBindings()
        bindings.removeAll { $0.vendorProductKey == key }
        try persist(bindings)
        AppLogger.shared.log("🗑️ [DeviceLayoutBindingStore] Removed binding for \(key)")
    }

    // MARK: - Persistence

    private func loadBindings() -> [Binding] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode([Binding].self, from: data)
        } catch {
            AppLogger.shared.warn("⚠️ [DeviceLayoutBindingStore] Failed to load bindings: \(error)")
            return []
        }
    }

    private func persist(_ bindings: [Binding]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(bindings)
        try data.write(to: fileURL, options: .atomic)
    }
}

#if DEBUG
    extension DeviceLayoutBindingStore {
        nonisolated static func testStore(at url: URL) -> DeviceLayoutBindingStore {
            DeviceLayoutBindingStore(fileURL: url)
        }
    }
#endif
