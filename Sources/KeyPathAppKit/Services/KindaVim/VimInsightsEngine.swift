// Stage-aware insight generator for the KindaVim Pack Detail panel.
//
// Pure function: takes a `KindaVimTelemetrySnapshot`, returns up to a
// few `VimInsight`s ordered by relevance for where the user is in
// their journey. No singletons, no side effects, no external calls.
//
// The headline metric is **arrow-key reliance**:
//   reliance = arrows / (arrows + hjkl)
//
// User stages are bucketed off that one number:
//   - .beginner   (>40% arrows)  → push them onto hjkl
//   - .intermediate (10–40%)     → fill foundation gaps + early efficiency
//   - .advanced   (<10%)         → richer optimization tips
//
// Each rule reports a `Glyph` (🌱 learn / ⚡ optimize / ⚠ shame) plus
// title/body strings. The view layer renders them as cards.

import Foundation

struct VimInsight: Identifiable, Equatable, Sendable {
    enum Glyph: String, Sendable {
        case learn = "🌱"
        case optimize = "⚡"
        case shame = "⚠️"
    }

    enum Stage: Equatable, Sendable {
        case beginner
        case intermediate
        case advanced
        case unknown  // not enough data
    }

    var id: String { title }
    let glyph: Glyph
    let title: String
    let body: String
    /// Higher = surfaced earlier. Within a single result list we keep
    /// the top three.
    let priority: Int
}

enum VimInsightsEngine {
    /// The fluency floor for "What you're using" tier labels. Hard-
    /// coded here rather than referencing the `@MainActor`-isolated
    /// `KindaVimTelemetryStore.fluencyThreshold` so the engine can run
    /// in a nonisolated context (tests, future server-side analysis).
    /// Must match `KindaVimTelemetryStore.fluencyThreshold`.
    static let fluencyThreshold = 10

    /// Produce up to `maxInsights` ordered insights for this snapshot.
    static func insights(
        for snapshot: KindaVimTelemetrySnapshot,
        maxInsights: Int = 3
    ) -> [VimInsight] {
        let stage = stage(for: snapshot)
        var candidates: [VimInsight] = []

        switch stage {
        case .unknown:
            // Not enough data yet; surface a single onboarding line.
            candidates.append(.init(
                glyph: .learn,
                title: "Get started",
                body: "Press a few vim keys (h, j, k, l) to populate your stats. Insights will sharpen as you go.",
                priority: 100
            ))
            return candidates

        case .beginner:
            candidates.append(contentsOf: beginnerInsights(snapshot))
        case .intermediate:
            candidates.append(contentsOf: intermediateInsights(snapshot))
        case .advanced:
            candidates.append(contentsOf: advancedInsights(snapshot))
        }

        // Universal rules (apply at every stage but ranked low so they
        // only surface when stage-specific rules are exhausted).
        candidates.append(contentsOf: universalInsights(snapshot))

        return Array(
            candidates
                .sorted { $0.priority > $1.priority }
                .prefix(maxInsights)
        )
    }

    // MARK: - Stage classification

    static func stage(for snapshot: KindaVimTelemetrySnapshot) -> VimInsight.Stage {
        let arrows = snapshot.nonVimNavigationFrequency.values.reduce(0, +)
        let hjkl = snapshot.commandFrequency
            .filter { ["h", "j", "k", "l"].contains($0.key) }
            .values.reduce(0, +)
        let total = arrows + hjkl
        guard total >= 50 else { return .unknown }
        let reliance = Double(arrows) / Double(total)
        if reliance > 0.4 { return .beginner }
        if reliance > 0.1 { return .intermediate }
        return .advanced
    }

    /// Headline metric for the chart subtitle / current-week summary.
    /// `nil` if there isn't enough data to produce a meaningful number.
    static func arrowReliancePercent(for snapshot: KindaVimTelemetrySnapshot) -> Double? {
        let arrows = snapshot.nonVimNavigationFrequency.values.reduce(0, +)
        let hjkl = snapshot.commandFrequency
            .filter { ["h", "j", "k", "l"].contains($0.key) }
            .values.reduce(0, +)
        let total = arrows + hjkl
        guard total > 0 else { return nil }
        return Double(arrows) * 100 / Double(total)
    }

    // MARK: - Beginner rules

    private static func beginnerInsights(_ snapshot: KindaVimTelemetrySnapshot) -> [VimInsight] {
        var out: [VimInsight] = []
        let reliance = arrowReliancePercent(for: snapshot) ?? 0

        out.append(.init(
            glyph: .shame,
            title: "Most of your cursor movement is still arrow keys",
            body: "Arrow reliance is at \(Int(reliance))%. The whole point of vim is that h, j, k, l live on the home row — try them deliberately for a day.",
            priority: 90
        ))

        if (snapshot.commandFrequency["h"] ?? 0) >= fluencyThreshold,
           (snapshot.commandFrequency["w"] ?? 0) < 5
        {
            out.append(.init(
                glyph: .learn,
                title: "Try `w` for word jumps",
                body: "You've internalised hjkl. The next motion to add is `w` (jump to next word) and `b` (jump back). They're how vim users skip across a line without holding `l`.",
                priority: 70
            ))
        }

        return out
    }

    // MARK: - Intermediate rules

    private static func intermediateInsights(_ snapshot: KindaVimTelemetrySnapshot) -> [VimInsight] {
        var out: [VimInsight] = []
        let reliance = arrowReliancePercent(for: snapshot) ?? 0

        if reliance > 20 {
            out.append(.init(
                glyph: .optimize,
                title: "You're still reaching for arrows \(Int(reliance))% of the time",
                body: "Most of those could be `h` and `l`. Force yourself to use them for a few days — it stops feeling forced fast.",
                priority: 80
            ))
        }

        // Foundation gaps
        if (snapshot.commandFrequency["w"] ?? 0) >= fluencyThreshold,
           (snapshot.commandFrequency["b"] ?? 0) < 5
        {
            out.append(.init(
                glyph: .learn,
                title: "Try `b` (word back)",
                body: "Pairs with `w` you already use. Together they replace double-clicking and arrow-spamming for word-level navigation.",
                priority: 75
            ))
        }
        // NOTE: we used to suggest learning `0` / `$` here, gated on
        // `commandFrequency["0"]` / `["4"]` being low. That's unsafe:
        // VimSequenceObserver records every typed character — including
        // count prefixes (`4j`, `14w`) — into `commandFrequency`. So a
        // user heavily relying on counts accumulates `"4"` presses
        // without ever using `$`, suppressing the suggestion. We can't
        // distinguish raw digits from shifted symbols without tracking
        // shift state, which we don't. Drop the rule rather than ship
        // false negatives.
        if (snapshot.commandFrequency["i"] ?? 0) >= fluencyThreshold,
           (snapshot.commandFrequency["a"] ?? 0) < 5
        {
            out.append(.init(
                glyph: .learn,
                title: "Try `a` (append after cursor)",
                body: "You're using `i` to enter insert before the cursor. `a` enters insert just after — saves a `→` press whenever you're inserting at the end of a word.",
                priority: 65
            ))
        }

        // Early efficiency tips
        let insertSeconds = snapshot.modeDwellSeconds["insert"] ?? 0
        let normalSeconds = snapshot.modeDwellSeconds["normal"] ?? 0
        let totalDwell = insertSeconds + normalSeconds
        if totalDwell > 600, insertSeconds / totalDwell > 0.7 {
            out.append(.init(
                glyph: .optimize,
                title: "You're in insert mode \(Int(insertSeconds * 100 / totalDwell))% of the time",
                body: "Most of vim's power lives in normal mode. Pop back out (Esc) more often — even between sentences — and your editing speed compounds.",
                priority: 60
            ))
        }

        return out
    }

    // MARK: - Advanced rules

    private static func advancedInsights(_ snapshot: KindaVimTelemetrySnapshot) -> [VimInsight] {
        var out: [VimInsight] = []

        // Operators without text objects
        let usesOperators = (snapshot.commandFrequency["d"] ?? 0) >= fluencyThreshold
            || (snapshot.commandFrequency["c"] ?? 0) >= fluencyThreshold
            || (snapshot.commandFrequency["y"] ?? 0) >= fluencyThreshold
        if usesOperators {
            out.append(.init(
                glyph: .learn,
                title: "Text objects are the next leap",
                body: "You're using operators like `d`, `c`, `y`. The next step is text objects — `daw` deletes a whole word including its space, `ci\"` changes everything inside the next quote pair. Ten new combinations, one mental model.",
                priority: 70
            ))
        }

        // Heavy `j` use without paragraph jumps
        let jCount = snapshot.commandFrequency["j"] ?? 0
        let bracketJumps = (snapshot.commandFrequency["["] ?? 0) + (snapshot.commandFrequency["]"] ?? 0)
        if jCount > 200, bracketJumps < 10 {
            out.append(.init(
                glyph: .optimize,
                title: "Try `}` and `{` for paragraph jumps",
                body: "You press `j` a lot. `}` jumps to the next paragraph break, `{` to the previous — much faster than holding `j` for long scrolls.",
                priority: 65
            ))
        }

        // Op-pending cancellation rate
        let completed = snapshot.operatorPendingCompleted
        let cancelled = snapshot.operatorPendingCancelled
        let totalOpPending = completed + cancelled
        if totalOpPending > 30 {
            let rate = Double(cancelled) * 100 / Double(totalOpPending)
            if rate > 30 {
                out.append(.init(
                    glyph: .optimize,
                    title: "You're cancelling \(Int(rate))% of operator sequences",
                    body: "After pressing `d`, `c`, or `y`, you're often pressing Esc instead of finishing with a motion. Slow down for a beat — the next press is just a normal motion (`w`, `}`, `i\"`, etc.) and the operator applies it.",
                    priority: 55
                ))
            }
        }

        return out
    }

    // MARK: - Universal rules (low-priority fallbacks)

    private static func universalInsights(_ snapshot: KindaVimTelemetrySnapshot) -> [VimInsight] {
        var out: [VimInsight] = []

        // Strategy mix awareness
        let kbSamples = snapshot.strategySamples["keyboard"] ?? 0
        let totalSamples = snapshot.strategySamples.values.reduce(0, +)
        if totalSamples > 20, Double(kbSamples) / Double(totalSamples) > 0.3 {
            out.append(.init(
                glyph: .optimize,
                title: "You spend a lot of time in Keyboard-strategy apps",
                body: "Apps like Slack force kindaVim into the Keyboard fallback, which drops `gg`, `G`, visual mode, and most text objects. Don't expect those to work there — they only work in Accessibility-strategy apps.",
                priority: 30
            ))
        }

        return out
    }
}
