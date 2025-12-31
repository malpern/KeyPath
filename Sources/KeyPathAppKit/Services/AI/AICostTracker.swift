import Foundation
import KeyPathCore

// MARK: - Pricing Constants

/// Claude API pricing constants (Claude 3.5 Sonnet, Dec 2024)
/// ⚠️ Update these when releasing new app versions
public enum ClaudeAPIPricing {
    /// Price per million input tokens ($3/1M)
    public static let inputPricePerMillion: Double = 3.0

    /// Price per million output tokens ($15/1M)
    public static let outputPricePerMillion: Double = 15.0

    /// Estimate cost based on token usage
    public static func estimateCost(inputTokens: Int, outputTokens: Int) -> Double {
        let inputCost = Double(inputTokens) / 1_000_000.0 * inputPricePerMillion
        let outputCost = Double(outputTokens) / 1_000_000.0 * outputPricePerMillion
        return inputCost + outputCost
    }
}

/// Centralized cost tracking for AI API usage
/// Shared between KanataConfigGenerator and AnthropicConfigRepairService
@MainActor
public final class AICostTracker {
    /// Shared instance
    public static let shared = AICostTracker()

    // MARK: - Constants

    /// UserDefaults key for cost history
    public static let costHistoryKey = "KeyPath.AI.CostHistory"

    /// Notification posted when cost history is updated
    public static let costUpdatedNotification = NSNotification.Name("KeyPath.AI.CostUpdated")

    /// Maximum entries to keep in history
    private static let maxHistoryEntries = 100

    private init() {}

    // MARK: - Cost Estimation

    /// Estimate cost based on token usage (convenience wrapper)
    public func estimateCost(inputTokens: Int, outputTokens: Int) -> Double {
        ClaudeAPIPricing.estimateCost(inputTokens: inputTokens, outputTokens: outputTokens)
    }

    // MARK: - Cost Entry Storage

    /// Source of the AI API call for tracking
    public enum CostSource: String {
        case configGenerator = "config-generator"
        case configRepair = "config-repair"
    }

    /// Store a cost entry in UserDefaults for history tracking
    /// - Parameters:
    ///   - inputTokens: Number of input tokens used
    ///   - outputTokens: Number of output tokens used
    ///   - estimatedCost: Estimated cost in USD
    ///   - source: Which service made the API call
    public func storeCostEntry(
        inputTokens: Int,
        outputTokens: Int,
        estimatedCost: Double,
        source: CostSource
    ) {
        var history = UserDefaults.standard.array(forKey: Self.costHistoryKey) as? [[String: Any]] ?? []

        let formatter = ISO8601DateFormatter()
        let entry: [String: Any] = [
            "timestamp": formatter.string(from: Date()),
            "inputTokens": inputTokens,
            "outputTokens": outputTokens,
            "estimatedCost": estimatedCost,
            "source": source.rawValue
        ]

        history.append(entry)

        // Keep only last N entries
        if history.count > Self.maxHistoryEntries {
            history = Array(history.suffix(Self.maxHistoryEntries))
        }

        UserDefaults.standard.set(history, forKey: Self.costHistoryKey)

        // Post notification for UI updates
        NotificationCenter.default.post(name: Self.costUpdatedNotification, object: nil)
    }

    /// Log usage and store cost entry (convenience method)
    public func trackUsage(
        inputTokens: Int,
        outputTokens: Int,
        source: CostSource,
        logPrefix: String = "ClaudeAPI"
    ) {
        let estimatedCost = estimateCost(inputTokens: inputTokens, outputTokens: outputTokens)
        AppLogger.shared.log(
            "💰 [\(logPrefix)] Used \(inputTokens) input + \(outputTokens) output tokens (~$\(String(format: "%.4f", estimatedCost)))"
        )
        storeCostEntry(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            estimatedCost: estimatedCost,
            source: source
        )
    }

    // MARK: - History Access

    /// Get all cost history entries
    public var costHistory: [[String: Any]] {
        UserDefaults.standard.array(forKey: Self.costHistoryKey) as? [[String: Any]] ?? []
    }

    /// Get total estimated cost from history
    public var totalEstimatedCost: Double {
        costHistory.reduce(0) { sum, entry in
            sum + (entry["estimatedCost"] as? Double ?? 0)
        }
    }

    /// Get total token usage from history
    public var totalTokens: (input: Int, output: Int) {
        costHistory.reduce((0, 0)) { sum, entry in
            (
                sum.0 + (entry["inputTokens"] as? Int ?? 0),
                sum.1 + (entry["outputTokens"] as? Int ?? 0)
            )
        }
    }

    /// Clear cost history
    public func clearHistory() {
        UserDefaults.standard.removeObject(forKey: Self.costHistoryKey)
        NotificationCenter.default.post(name: Self.costUpdatedNotification, object: nil)
        AppLogger.shared.log("🗑️ [AICostTracker] Cost history cleared")
    }
}
