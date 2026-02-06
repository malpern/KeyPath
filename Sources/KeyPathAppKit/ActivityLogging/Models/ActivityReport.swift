import Foundation

/// Time period for activity reports
public enum ReportPeriod: String, CaseIterable, Sendable {
    case daily = "Today"
    case weekly = "This Week"
    case monthly = "This Month"

    /// Get the date interval for this period
    public var dateInterval: DateInterval {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .daily:
            let start = calendar.startOfDay(for: now)
            return DateInterval(start: start, end: now)

        case .weekly:
            let start = calendar.date(from: calendar.dateComponents(
                [.yearForWeekOfYear, .weekOfYear],
                from: now
            )) ?? now
            return DateInterval(start: start, end: now)

        case .monthly:
            let start = calendar.date(from: calendar.dateComponents(
                [.year, .month],
                from: now
            )) ?? now
            return DateInterval(start: start, end: now)
        }
    }
}

/// Aggregated activity report for a time period
public struct ActivityReport: Sendable {
    public let period: ReportPeriod
    public let generatedAt: Date
    public let totalEvents: Int
    public let appUsage: [AppUsageSummary]
    public let topShortcuts: [ShortcutSummary]
    public let keyPathActions: [ActionSummary]

    public init(
        period: ReportPeriod,
        generatedAt: Date = Date(),
        totalEvents: Int,
        appUsage: [AppUsageSummary],
        topShortcuts: [ShortcutSummary],
        keyPathActions: [ActionSummary]
    ) {
        self.period = period
        self.generatedAt = generatedAt
        self.totalEvents = totalEvents
        self.appUsage = appUsage
        self.topShortcuts = topShortcuts
        self.keyPathActions = keyPathActions
    }

    /// Empty report for when no data exists
    public static func empty(for period: ReportPeriod) -> ActivityReport {
        ActivityReport(
            period: period,
            totalEvents: 0,
            appUsage: [],
            topShortcuts: [],
            keyPathActions: []
        )
    }
}

/// Summary of app usage (launches and switches)
public struct AppUsageSummary: Identifiable, Sendable {
    public var id: String {
        bundleIdentifier
    }

    public let bundleIdentifier: String
    public let appName: String
    public let launchCount: Int
    public let switchCount: Int

    public init(
        bundleIdentifier: String,
        appName: String,
        launchCount: Int,
        switchCount: Int
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.launchCount = launchCount
        self.switchCount = switchCount
    }

    /// Total interactions (launches + switches)
    public var totalInteractions: Int {
        launchCount + switchCount
    }
}

/// Summary of keyboard shortcut usage
public struct ShortcutSummary: Identifiable, Sendable {
    public var id: String {
        shortcut
    }

    public let shortcut: String // Display string like "⌘S"
    public let count: Int

    public init(shortcut: String, count: Int) {
        self.shortcut = shortcut
        self.count = count
    }
}

/// Summary of KeyPath action usage
public struct ActionSummary: Identifiable, Sendable {
    public var id: String {
        "\(action):\(target ?? "")"
    }

    public let action: String
    public let target: String?
    public let count: Int

    public init(action: String, target: String?, count: Int) {
        self.action = action
        self.target = target
        self.count = count
    }

    /// Display string for the action
    public var displayString: String {
        if let target {
            return "\(action): \(target)"
        }
        return action
    }
}
