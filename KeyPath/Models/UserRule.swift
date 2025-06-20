import Foundation

/// Represents a user-created rule with state management
struct UserRule: Codable, Identifiable {
    let id: UUID
    let kanataRule: KanataRule
    var isActive: Bool
    let dateCreated: Date
    var dateModified: Date
    var backupPath: String?
    
    init(kanataRule: KanataRule, backupPath: String? = nil) {
        self.id = UUID()
        self.kanataRule = kanataRule
        self.isActive = true // New rules are active by default
        self.dateCreated = Date()
        self.dateModified = Date()
        self.backupPath = backupPath
    }
    
    mutating func setActive(_ active: Bool) {
        self.isActive = active
        self.dateModified = Date()
    }
}

/// Represents a deleted rule with retention period
struct DeletedRule: Codable, Identifiable {
    let id: UUID
    let originalRule: UserRule
    let deletedDate: Date
    let backupPath: String?
    
    init(userRule: UserRule) {
        self.id = UUID()
        self.originalRule = userRule
        self.deletedDate = Date()
        self.backupPath = userRule.backupPath
    }
    
    /// Check if this deleted rule should be permanently removed (48 hours old)
    var shouldPermanentlyDelete: Bool {
        let fortyEightHoursAgo = Date().addingTimeInterval(-48 * 60 * 60)
        return deletedDate < fortyEightHoursAgo
    }
}

/// Enhanced rule manager that handles user rules, activation state, and deletion
@Observable
class UserRuleManager {
    var activeRules: [UserRule] = []
    private var deletedRules: [DeletedRule] = []
    
    private let activeRulesKey = "KeyPath.UserRules.Active"
    private let deletedRulesKey = "KeyPath.UserRules.Deleted"
    private let kanataInstaller = KanataInstaller()
    
    init() {
        loadRules()
        cleanupOldDeletedRules()
    }
    
    // MARK: - Rule Management
    
    /// Add a new rule and activate it in Kanata config
    func addRule(_ kanataRule: KanataRule, completion: @escaping (Result<UserRule, Error>) -> Void) {
        let userRule = UserRule(kanataRule: kanataRule)
        
        // Install the rule in Kanata config
        kanataInstaller.installRule(kanataRule) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let backupPath):
                    var updatedRule = userRule
                    updatedRule.backupPath = backupPath
                    
                    self?.activeRules.insert(updatedRule, at: 0) // New rules at top
                    self?.saveActiveRules()
                    completion(.success(updatedRule))
                    
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Toggle rule activation state
    func toggleRule(_ ruleId: UUID, completion: @escaping (Result<Bool, Error>) -> Void) {
        guard let index = activeRules.firstIndex(where: { $0.id == ruleId }) else {
            completion(.failure(RuleManagerError.ruleNotFound))
            return
        }
        
        let newActiveState = !activeRules[index].isActive
        activeRules[index].setActive(newActiveState)
        
        if newActiveState {
            // Reactivate rule
            kanataInstaller.installRule(activeRules[index].kanataRule) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let backupPath):
                        self?.activeRules[index].backupPath = backupPath
                        self?.saveActiveRules()
                        completion(.success(true))
                    case .failure(let error):
                        // Revert state on failure
                        self?.activeRules[index].setActive(!newActiveState)
                        completion(.failure(error))
                    }
                }
            }
        } else {
            // Deactivate rule - remove from Kanata config but keep in memory
            regenerateKanataConfig { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self?.saveActiveRules()
                        completion(.success(false))
                    case .failure(let error):
                        // Revert state on failure
                        self?.activeRules[index].setActive(!newActiveState)
                        completion(.failure(error))
                    }
                }
            }
        }
    }
    
    /// Delete a rule permanently (with 48-hour backup retention)
    func deleteRule(_ ruleId: UUID, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let index = activeRules.firstIndex(where: { $0.id == ruleId }) else {
            completion(.failure(RuleManagerError.ruleNotFound))
            return
        }
        
        let ruleToDelete = activeRules[index]
        let deletedRule = DeletedRule(userRule: ruleToDelete)
        
        // Move to deleted rules for 48-hour retention
        deletedRules.append(deletedRule)
        activeRules.remove(at: index)
        
        // Regenerate Kanata config without this rule
        regenerateKanataConfig { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.saveActiveRules()
                    self?.saveDeletedRules()
                    completion(.success(()))
                case .failure(let error):
                    // Revert deletion on failure
                    self?.activeRules.insert(ruleToDelete, at: index)
                    if let deletedIndex = self?.deletedRules.firstIndex(where: { $0.id == deletedRule.id }) {
                        self?.deletedRules.remove(at: deletedIndex)
                    }
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Get all rules sorted by creation date (newest first)
    var allRules: [UserRule] {
        return activeRules.sorted { $0.dateCreated > $1.dateCreated }
    }
    
    /// Get only active rules
    var enabledRules: [UserRule] {
        return activeRules.filter { $0.isActive }
    }
    
    // MARK: - Kanata Config Management
    
    private func regenerateKanataConfig(completion: @escaping (Result<Void, Error>) -> Void) {
        // Get all currently active rules
        let activeKanataRules = enabledRules.map { $0.kanataRule }
        
        // Use KanataConfigManager to regenerate the complete config
        let configManager = KanataConfigManager()
        
        // This would need to be implemented in KanataConfigManager
        // to rebuild the entire config with only active rules
        configManager.regenerateConfigWithRules(activeKanataRules) { result in
            completion(result)
        }
    }
    
    // MARK: - Persistence
    
    private func saveActiveRules() {
        if let encoded = try? JSONEncoder().encode(activeRules) {
            UserDefaults.standard.set(encoded, forKey: activeRulesKey)
        }
    }
    
    private func saveDeletedRules() {
        if let encoded = try? JSONEncoder().encode(deletedRules) {
            UserDefaults.standard.set(encoded, forKey: deletedRulesKey)
        }
    }
    
    private func loadRules() {
        // Load active rules
        if let data = UserDefaults.standard.data(forKey: activeRulesKey),
           let decoded = try? JSONDecoder().decode([UserRule].self, from: data) {
            activeRules = decoded
        }
        
        // Load deleted rules
        if let data = UserDefaults.standard.data(forKey: deletedRulesKey),
           let decoded = try? JSONDecoder().decode([DeletedRule].self, from: data) {
            deletedRules = decoded
        }
    }
    
    private func cleanupOldDeletedRules() {
        let originalCount = deletedRules.count
        deletedRules.removeAll { $0.shouldPermanentlyDelete }
        
        if deletedRules.count != originalCount {
            saveDeletedRules()
        }
    }
}

enum RuleManagerError: Error, LocalizedError {
    case ruleNotFound
    case configRegenerationFailed
    
    var errorDescription: String? {
        switch self {
        case .ruleNotFound:
            return "Rule not found"
        case .configRegenerationFailed:
            return "Failed to regenerate Kanata configuration"
        }
    }
}

// MARK: - Extensions for KanataConfigManager

extension KanataConfigManager {
    /// Regenerate the entire Kanata config with only the provided rules
    func regenerateConfigWithRules(_ rules: [KanataRule], completion: @escaping (Result<Void, Error>) -> Void) {
        // Read the base configuration
        let configPath = NSString(string: "~/.config/kanata/kanata.kbd").expandingTildeInPath
        
        do {
            let baseConfig = try String(contentsOfFile: configPath, encoding: .utf8)
            var config = parseConfig(baseConfig)
            
            // Clear existing rules (keep base config like defcfg)
            config.defsrc = []
            config.deflayer = ["default": []]
            config.additionalSections = []
            
            // Add all active rules
            for rule in rules {
                addKanataRule(rule.completeKanataConfig, to: &config)
            }
            
            // Generate and write the new config
            let newConfig = generateConfig(config)
            try newConfig.write(toFile: configPath, atomically: true, encoding: .utf8)
            
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }
}