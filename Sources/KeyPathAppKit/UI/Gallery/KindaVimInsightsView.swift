// Insights area for the KindaVim Pack Detail panel. Three sections,
// only rendered when telemetry is opted in:
//   1. Headline arrow-key reliance chart (30 days)
//   2. "What you're using" — top-N command bars with mastery tiers
//   3. "What to try next" — up to 3 insights from `VimInsightsEngine`
// Plus a one-line secondary stats row at the bottom.
//
// The chart and bars react to a periodic refresh (every few seconds)
// rather than every keypress — telemetry is debounced anyway, so the
// cached snapshot only updates on disk-flush boundaries.

import Charts
import SwiftUI

@MainActor
struct KindaVimInsightsView: View {
    @State private var snapshot = KindaVimTelemetrySnapshot()
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            arrowReliabilityChart
            usageBars
            insightCards
            secondaryStats
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
        .onAppear { refresh(force: true) }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private func refresh(force: Bool = false) {
        // Force any debounced writes to disk so the snapshot we read is
        // current. Cheap when there's nothing pending.
        KindaVimTelemetryStore.shared.flushNow()
        snapshot = KindaVimTelemetryStore.shared.loadSnapshot()
        if force, refreshTimer == nil {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                Task { @MainActor in
                    KindaVimTelemetryStore.shared.flushNow()
                    snapshot = KindaVimTelemetryStore.shared.loadSnapshot()
                }
            }
        }
    }

    // MARK: - Headline chart

    @ViewBuilder
    private var arrowReliabilityChart: some View {
        let series = chartSeries
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                sectionHeader("Arrow-key reliance · last 30 days")
                Text("Lower is better — less reaching for the arrow keys.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if series.count < 2 {
                emptyChartCard
            } else {
                chart(for: series)
                    .frame(height: 110)
                Text(chartSubtitle(series: series))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
            }
        }
    }

    private var emptyChartCard: some View {
        Text("Use vim for a few days and a chart will appear here.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.06))
            )
    }

    @ChartContentBuilder
    private func chartMarks(_ series: [ChartPoint]) -> some ChartContent {
        // Area gradient under the line — Apple Health / Stocks pattern.
        ForEach(series) { point in
            AreaMark(
                x: .value("Day", point.date),
                y: .value("Arrow %", point.percent)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color.green.opacity(0.35),
                        Color.green.opacity(0.05),
                        Color.clear,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }

        // Thin, semantically-green line on top of the gradient. Green
        // because the *trend* (going down) is good — users will read
        // "green = good" before parsing the inverted axis.
        ForEach(series) { point in
            LineMark(
                x: .value("Day", point.date),
                y: .value("Arrow %", point.percent)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(Color.green.gradient)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
        }

        // Emphasize the most recent point + the lowest-ever point so
        // the user's eye lands on "where I am now" and "best so far."
        if let recent = series.last {
            PointMark(
                x: .value("Day", recent.date),
                y: .value("Arrow %", recent.percent)
            )
            .foregroundStyle(Color.green)
            .symbolSize(60)
        }
        if let best = series.min(by: { $0.percent < $1.percent }),
           best.id != series.last?.id
        {
            PointMark(
                x: .value("Day", best.date),
                y: .value("Arrow %", best.percent)
            )
            .foregroundStyle(Color.green.opacity(0.55))
            .symbolSize(35)
        }
    }

    private func chart(for series: [ChartPoint]) -> some View {
        Chart {
            chartMarks(series)
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            // Just 0 and 100 — anything else clutters this size.
            AxisMarks(position: .leading, values: [0, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2]))
                    .foregroundStyle(Color.secondary.opacity(0.3))
                AxisValueLabel {
                    if let percent = value.as(Int.self) {
                        Text("\(percent)%")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            // Weekly grid, no labels — dates clutter at this scale.
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2]))
                    .foregroundStyle(Color.secondary.opacity(0.2))
            }
        }
        .animation(.easeInOut(duration: 0.6), value: series)
        .accessibilityLabel("Arrow-key reliance over the last 30 days")
        .accessibilityValue(accessibilityChartSummary(series: series))
    }

    private func accessibilityChartSummary(series: [ChartPoint]) -> String {
        guard let last = series.last else { return "No data yet." }
        let now = Int(last.percent)
        guard let first = series.first, series.count >= 2 else {
            return "Currently \(now) percent."
        }
        let then = Int(first.percent)
        let direction = now < then ? "down" : (now > then ? "up" : "flat")
        return "Currently \(now) percent, \(direction) from \(then) percent at the start of the window."
    }

    private struct ChartPoint: Identifiable, Equatable {
        let date: Date
        let percent: Double
        var id: Date { date }
    }

    private var chartSeries: [ChartPoint] {
        let last30 = snapshot.dailySnapshots.suffix(30)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return last30.compactMap { day in
            let total = day.nonVimNavigationCount + day.hjklCount
            guard total > 0 else { return nil }
            guard let parsed = formatter.date(from: day.date) else { return nil }
            let pct = Double(day.nonVimNavigationCount) * 100 / Double(total)
            return ChartPoint(date: parsed, percent: pct)
        }
    }

    private func chartSubtitle(series: [ChartPoint]) -> String {
        guard let last = series.last else { return "" }
        let now = Int(last.percent)
        guard let first = series.first, series.count >= 7 else {
            return "Now: \(now)%."
        }
        let then = Int(first.percent)
        let delta = then - now
        if delta > 5 {
            return "Now: \(now)% — down \(delta) points from \(then)%. ↓"
        } else if delta < -5 {
            return "Now: \(now)% — up \(-delta) points from \(then)%."
        }
        return "Now: \(now)% — holding steady around \(then)%."
    }

    // MARK: - Usage bars

    @ViewBuilder
    private var usageBars: some View {
        let entries = topCommands
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("What you're using")
            if entries.isEmpty {
                Text("No commands recorded yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                let maxCount = entries.first?.count ?? 1
                ForEach(entries, id: \.key) { entry in
                    usageRow(entry: entry, maxCount: maxCount)
                }
            }
        }
    }

    private struct UsageEntry {
        let key: String
        let count: Int
        let displayLabel: String
        let tier: MasteryTier
    }

    private enum MasteryTier: String {
        case untried = "Untried"
        case learning = "Learning"
        case comfortable = "Comfortable"
        case fluent = "Fluent"
    }

    private static func tier(for count: Int) -> MasteryTier {
        switch count {
        case 0: return .untried
        case 1...9: return .learning
        case 10...99: return .comfortable
        default: return .fluent
        }
    }

    private var topCommands: [UsageEntry] {
        snapshot.commandFrequency
            .map { (key, count) in
                UsageEntry(
                    key: key,
                    count: count,
                    displayLabel: Self.displayLabel(for: key),
                    tier: Self.tier(for: count)
                )
            }
            .sorted { $0.count > $1.count }
            .prefix(12)
            .map { $0 }
    }

    /// Translate the kanata physical-key name we record into the
    /// human-readable label we want to show ("slash" → "/").
    private static func displayLabel(for key: String) -> String {
        switch key {
        case "slash": return "/"
        case "0": return "0"
        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            return key
        default: return key
        }
    }

    private func usageRow(entry: UsageEntry, maxCount: Int) -> some View {
        HStack(spacing: 10) {
            Text(entry.displayLabel)
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .frame(width: 26, alignment: .leading)
            GeometryReader { geo in
                let fraction = CGFloat(entry.count) / CGFloat(max(maxCount, 1))
                let width = geo.size.width * fraction
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: barGradient(for: entry.tier),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: width, height: 6)
                }
            }
            .frame(height: 6)
            .animation(.spring(response: 0.55, dampingFraction: 0.8), value: entry.count)
            Text("\(entry.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.4), value: entry.count)
            Text(entry.tier.rawValue)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(tierColor(entry.tier))
                .frame(width: 80, alignment: .leading)
        }
    }

    /// Gradient sweep that visually maps to mastery tier — Untried fades
    /// to a flat secondary, Learning warms toward orange, Comfortable
    /// to blue, Fluent to green. Same semantic palette as `tierColor`.
    private func barGradient(for tier: MasteryTier) -> [Color] {
        switch tier {
        case .untried: return [Color.secondary.opacity(0.3), Color.secondary.opacity(0.15)]
        case .learning: return [Color.orange.opacity(0.85), Color.orange.opacity(0.45)]
        case .comfortable: return [Color.blue.opacity(0.85), Color.blue.opacity(0.45)]
        case .fluent: return [Color.green.opacity(0.85), Color.green.opacity(0.45)]
        }
    }

    private func tierColor(_ tier: MasteryTier) -> Color {
        switch tier {
        case .untried: return .secondary
        case .learning: return .orange
        case .comfortable: return .blue
        case .fluent: return .green
        }
    }

    // MARK: - Insight cards

    @ViewBuilder
    private var insightCards: some View {
        let insights = VimInsightsEngine.insights(for: snapshot)
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("What to try next")
            if insights.isEmpty {
                Text("No suggestions yet — keep using the pack and tips will appear here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(insights) { insight in
                    insightCard(insight)
                }
            }
        }
    }

    private func insightCard(_ insight: VimInsight) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(insight.glyph.rawValue)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.system(size: 12, weight: .semibold))
                Text(insight.body)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    // MARK: - Secondary stats

    private var secondaryStats: some View {
        let vocab = snapshot.commandFrequency.values
            .filter { $0 >= VimInsightsEngine.fluencyThreshold }
            .count
        let normalSec = snapshot.modeDwellSeconds["normal"] ?? 0
        let insertSec = snapshot.modeDwellSeconds["insert"] ?? 0
        let total = normalSec + insertSec
        let normalPct = total > 0 ? Int(normalSec * 100 / total) : 0

        return HStack(spacing: 16) {
            statChip(label: "Vocabulary", value: "\(vocab) fluent")
            statChip(label: "Normal mode", value: total > 0 ? "\(normalPct)%" : "—")
            Spacer()
        }
    }

    private func statChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}
