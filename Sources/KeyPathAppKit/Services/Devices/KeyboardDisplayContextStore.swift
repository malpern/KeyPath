import Foundation
import KeyPathCore

/// Persists keyboard-specific display context without changing global Kanata rules.
///
/// This stores only how KeyPath should visualize a given keyboard:
/// - physical layout selection
/// - logical keymap selection
/// - punctuation label preference
///
/// File: `~/.config/keypath/KeyboardDisplayContexts.json`
actor KeyboardDisplayContextStore {
    static let shared = KeyboardDisplayContextStore()

    struct Context: Codable, Equatable, Sendable {
        let vendorProductKey: String
        let layoutId: String
        let keymapId: String
        let includePunctuationStore: String
        let keyboardName: String
        var updatedAt: Date
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
        self.fileURL = fileURL ?? defaultDirectory.appendingPathComponent("KeyboardDisplayContexts.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func context(vendorProductKey: String) -> Context? {
        loadContexts().first { $0.vendorProductKey == vendorProductKey }
    }

    func allContexts() -> [Context] {
        loadContexts()
    }

    func saveContext(_ context: Context) throws {
        var contexts = loadContexts()
        contexts.removeAll { $0.vendorProductKey == context.vendorProductKey }
        contexts.append(context)
        try persist(contexts)
        AppLogger.shared.log("💾 [KeyboardDisplayContextStore] Saved context: \(context.keyboardName) → \(context.layoutId) / \(context.keymapId)")
    }

    func removeContext(vendorProductKey: String) throws {
        var contexts = loadContexts()
        contexts.removeAll { $0.vendorProductKey == vendorProductKey }
        try persist(contexts)
        AppLogger.shared.log("🗑️ [KeyboardDisplayContextStore] Removed context for \(vendorProductKey)")
    }

    private func loadContexts() -> [Context] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode([Context].self, from: data)
        } catch {
            AppLogger.shared.warn("⚠️ [KeyboardDisplayContextStore] Failed to load contexts: \(error)")
            return []
        }
    }

    private func persist(_ contexts: [Context]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(contexts)
        try data.write(to: fileURL, options: .atomic)
    }
}

#if DEBUG
    extension KeyboardDisplayContextStore {
        nonisolated static func testStore(at url: URL) -> KeyboardDisplayContextStore {
            KeyboardDisplayContextStore(fileURL: url)
        }
    }
#endif
