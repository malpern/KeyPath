import Foundation
import Observation

struct RuleHistoryItem: Codable, Identifiable {
    let id: UUID
    let rule: KanataRule
    let timestamp: Date
    let backupPath: String

    init(rule: KanataRule, timestamp: Date, backupPath: String) {
        self.id = UUID()
        self.rule = rule
        self.timestamp = timestamp
        self.backupPath = backupPath
    }
}

@Observable
class RuleHistory {
    var items: [RuleHistoryItem] = []

    private let storageKey = "KeyPath.RuleHistory"
    private let maxHistoryItems = 20

    init() {
        loadHistory()
    }

    func addRule(_ rule: KanataRule, backupPath: String) {
        let item = RuleHistoryItem(
            rule: rule,
            timestamp: Date(),
            backupPath: backupPath
        )

        items.insert(item, at: 0)

        // Limit history size
        if items.count > maxHistoryItems {
            items = Array(items.prefix(maxHistoryItems))
        }

        saveHistory()
    }

    func getLastRule() -> RuleHistoryItem? {
        return items.first
    }

    func removeLastRule() {
        if !items.isEmpty {
            items.removeFirst()
            saveHistory()
        }
    }

    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([RuleHistoryItem].self, from: data) {
            items = decoded
        }
    }
}
