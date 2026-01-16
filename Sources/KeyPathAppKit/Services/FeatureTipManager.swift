import Foundation

/// Tracks learning state for a contextual tip with spaced repetition logic.
/// - Initial learning requires 6 successful uses
/// - If unused for 5 weeks, assumes forgotten and resets
/// - Relearning only requires 3 uses (user has seen it before)
struct TipLearningState: Codable, Equatable {
    var useCount: Int = 0
    var lastUsedDate: Date?
    var hasEverLearned: Bool = false

    /// Number of uses required to mark as learned
    var requiredUses: Int {
        hasEverLearned ? 3 : 6 // Relearning vs initial learning
    }

    /// Whether the tip has been sufficiently learned
    var isLearned: Bool {
        useCount >= requiredUses
    }

    /// Check if enough time has passed that the user likely forgot
    /// (5 weeks without use)
    var isForgotten: Bool {
        guard let lastUsed = lastUsedDate else { return false }
        let fiveWeeks: TimeInterval = 5 * 7 * 24 * 60 * 60
        return Date().timeIntervalSince(lastUsed) > fiveWeeks
    }

    /// Record a successful use of the feature
    mutating func recordUse() {
        useCount += 1
        lastUsedDate = Date()
        if isLearned {
            hasEverLearned = true
        }
    }

    /// Check for forgetting and reset if necessary
    /// Call this before checking shouldShow
    mutating func checkAndResetIfForgotten() {
        if isForgotten, isLearned {
            // Reset count but keep hasEverLearned = true for lower relearning threshold
            useCount = 0
        }
    }
}

/// Manages contextual feature tips with learning-based visibility.
/// Tips are shown until the user demonstrates they've learned the feature,
/// with automatic reset if the feature goes unused for too long.
@MainActor
final class FeatureTipManager: ObservableObject {
    static let shared = FeatureTipManager()

    /// Identifiers for trackable tips
    enum TipID: String, CaseIterable {
        case hideOverlayShortcut = "tip.hideOverlayShortcut"
        case drawerToggle = "tip.drawerToggle"
        case layerSwitching = "tip.layerSwitching"
        // Add more tips here as needed
    }

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Cache of loaded learning states
    private var stateCache: [TipID: TipLearningState] = [:]

    private init() {}

    // MARK: - Debug Mode

    /// Debug flag to always show tips regardless of learned state
    var debugAlwaysShowTips: Bool {
        get { defaults.bool(forKey: "debug.alwaysShowTips") }
        set { defaults.set(newValue, forKey: "debug.alwaysShowTips") }
    }

    // MARK: - Public API

    /// Check if a tip should be shown
    /// Returns true if not yet learned (or debug mode is on)
    func shouldShow(_ tip: TipID) -> Bool {
        if debugAlwaysShowTips { return true }

        var state = loadState(for: tip)
        state.checkAndResetIfForgotten()
        saveState(state, for: tip)

        return !state.isLearned
    }

    /// Record a successful use of the feature associated with this tip
    /// Call this when the user successfully performs the action
    func recordUse(_ tip: TipID) {
        var state = loadState(for: tip)
        state.recordUse()
        saveState(state, for: tip)

        if state.isLearned {
            objectWillChange.send()
        }
    }

    /// Get the current learning state for a tip (for UI display)
    func learningState(for tip: TipID) -> TipLearningState {
        loadState(for: tip)
    }

    /// Check if a tip has been learned
    func isLearned(_ tip: TipID) -> Bool {
        var state = loadState(for: tip)
        state.checkAndResetIfForgotten()
        return state.isLearned
    }

    /// Reset learning state for a specific tip
    func reset(_ tip: TipID) {
        stateCache.removeValue(forKey: tip)
        defaults.removeObject(forKey: tip.rawValue)
        objectWillChange.send()
    }

    /// Reset all tips (for testing/debugging)
    func resetAll() {
        stateCache.removeAll()
        for tip in TipID.allCases {
            defaults.removeObject(forKey: tip.rawValue)
        }
        objectWillChange.send()
    }

    // MARK: - Persistence

    private func loadState(for tip: TipID) -> TipLearningState {
        if let cached = stateCache[tip] {
            return cached
        }

        guard let data = defaults.data(forKey: tip.rawValue),
              let state = try? decoder.decode(TipLearningState.self, from: data)
        else {
            return TipLearningState()
        }

        stateCache[tip] = state
        return state
    }

    private func saveState(_ state: TipLearningState, for tip: TipID) {
        stateCache[tip] = state
        if let data = try? encoder.encode(state) {
            defaults.set(data, forKey: tip.rawValue)
        }
    }
}
