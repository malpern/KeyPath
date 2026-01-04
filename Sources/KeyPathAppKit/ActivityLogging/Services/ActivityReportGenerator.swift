import Foundation
import KeyPathCore

/// Generates activity reports from stored events
public actor ActivityReportGenerator {
    // MARK: - Singleton

    public static let shared = ActivityReportGenerator()

    private let storage = ActivityLogStorage.shared

    private init() {}

    // MARK: - Report Generation

    /// Generate a report for the specified period
    public func generateReport(for period: ReportPeriod) async -> ActivityReport {
        let interval = period.dateInterval

        do {
            let events = try await storage.readEvents(
                from: interval.start,
                to: interval.end
            )

            return buildReport(from: events, period: period)
        } catch {
            AppLogger.shared.log("❌ [ActivityReportGenerator] Failed to read events: \(error.localizedDescription)")
            return .empty(for: period)
        }
    }

    // MARK: - Private Helpers

    private func buildReport(from events: [ActivityEvent], period: ReportPeriod) -> ActivityReport {
        // Aggregate app usage
        var appLaunches: [String: (name: String, count: Int)] = [:]
        var appSwitches: [String: (name: String, count: Int)] = [:]

        // Aggregate shortcuts
        var shortcuts: [String: Int] = [:]

        // Aggregate KeyPath actions
        var actions: [String: (target: String?, count: Int)] = [:]

        for event in events {
            switch event.payload {
            case let .app(data):
                if data.isLaunch {
                    let existing = appLaunches[data.bundleIdentifier]
                    appLaunches[data.bundleIdentifier] = (
                        name: data.appName,
                        count: (existing?.count ?? 0) + 1
                    )
                } else {
                    let existing = appSwitches[data.bundleIdentifier]
                    appSwitches[data.bundleIdentifier] = (
                        name: data.appName,
                        count: (existing?.count ?? 0) + 1
                    )
                }

            case let .shortcut(data):
                let key = data.displayString
                shortcuts[key] = (shortcuts[key] ?? 0) + 1

            case let .action(data):
                let key = "\(data.action):\(data.target ?? "")"
                let existing = actions[key]
                actions[key] = (
                    target: data.target,
                    count: (existing?.count ?? 0) + 1
                )
            }
        }

        // Build app usage summaries
        let appUsage = buildAppUsageSummaries(
            launches: appLaunches,
            switches: appSwitches
        )

        // Build shortcut summaries
        let topShortcuts = shortcuts
            .map { ShortcutSummary(shortcut: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(20)

        // Build action summaries
        let keyPathActions = actions
            .map { key, value -> ActionSummary in
                let parts = key.split(separator: ":", maxSplits: 1)
                let action = String(parts.first ?? "")
                let target = parts.count > 1 ? String(parts[1]) : nil
                return ActionSummary(action: action, target: target, count: value.count)
            }
            .sorted { $0.count > $1.count }

        return ActivityReport(
            period: period,
            totalEvents: events.count,
            appUsage: appUsage,
            topShortcuts: Array(topShortcuts),
            keyPathActions: keyPathActions
        )
    }

    private func buildAppUsageSummaries(
        launches: [String: (name: String, count: Int)],
        switches: [String: (name: String, count: Int)]
    ) -> [AppUsageSummary] {
        // Combine all bundle identifiers
        var allBundleIds = Set(launches.keys)
        allBundleIds.formUnion(switches.keys)

        let summaries = allBundleIds.map { bundleId -> AppUsageSummary in
            let launchData = launches[bundleId]
            let switchData = switches[bundleId]

            return AppUsageSummary(
                bundleIdentifier: bundleId,
                appName: launchData?.name ?? switchData?.name ?? bundleId,
                launchCount: launchData?.count ?? 0,
                switchCount: switchData?.count ?? 0
            )
        }

        // Sort by total interactions (switches + launches)
        return summaries
            .sorted { $0.totalInteractions > $1.totalInteractions }
            .prefix(20)
            .map { $0 }
    }
}
