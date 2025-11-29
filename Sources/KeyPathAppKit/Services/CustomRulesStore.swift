import Foundation
import KeyPathCore

/// Persists user-defined custom rules alongside the main configuration directory.
actor CustomRulesStore {
    static let shared = CustomRulesStore()

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let defaultDirectory = URL(
            fileURLWithPath: WizardSystemPaths.userConfigDirectory, isDirectory: true
        )
        self.fileURL = fileURL ?? defaultDirectory.appendingPathComponent("CustomRules.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadRules() -> [CustomRule] {
        AppLogger.shared.log("📂 [CustomRulesStore] loadRules from: \(fileURL.path)")
        guard fileManager.fileExists(atPath: fileURL.path) else {
            AppLogger.shared.log("📂 [CustomRulesStore] File does not exist, returning []")
            return []
        }
        do {
            let data = try Data(contentsOf: fileURL)
            AppLogger.shared.log("📂 [CustomRulesStore] Read \(data.count) bytes from file")
            let rules = try decoder.decode([CustomRule].self, from: data)
            AppLogger.shared.log("📂 [CustomRulesStore] Decoded \(rules.count) rules:")
            for rule in rules {
                AppLogger.shared.log("📂 [CustomRulesStore]   - '\(rule.input)' → '\(rule.output)' (enabled: \(rule.isEnabled))")
            }
            return rules
        } catch {
            AppLogger.shared.log("⚠️ [CustomRulesStore] Failed to load rules: \(error)")
            return []
        }
    }

    func saveRules(_ rules: [CustomRule]) throws {
        AppLogger.shared.log("💾 [CustomRulesStore] saveRules: \(rules.count) rules to \(fileURL.path)")
        for rule in rules {
            AppLogger.shared.log("💾 [CustomRulesStore]   - '\(rule.input)' → '\(rule.output)' (enabled: \(rule.isEnabled))")
        }
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(rules)
        try data.write(to: fileURL, options: .atomic)
        AppLogger.shared.log("💾 [CustomRulesStore] Saved \(data.count) bytes")
    }
}

#if DEBUG
    extension CustomRulesStore {
        nonisolated static func testStore(at url: URL) -> CustomRulesStore {
            CustomRulesStore(fileURL: url)
        }
    }
#endif
