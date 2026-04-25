// Local-only, opt-in usage counters for the KindaVim Mode Display pack.
//
// Privacy invariants — these are *the* design constraints, not soft
// preferences:
// 1. **Off by default.** No data is recorded until the user explicitly
//    opts in via the toggle in Pack Detail.
// 2. **Local-only.** Data is written to a single JSON file at
//    `~/Library/Application Support/KeyPath/kindavim-telemetry.json`.
//    KeyPath never reads this file off-device, never uploads it, never
//    transmits it. The data never leaves the user's Mac.
// 3. **User-deletable.** A "Clear all data" button in Pack Detail wipes
//    the file at any time, no questions asked.
// 4. **Aggregate counters only.** We record *frequencies* (how many
//    times the user pressed `h`), not *sequences* (the order of
//    keystrokes). No timestamps on individual keys, no full keystroke
//    log, nothing that could reconstruct a session.
//
// Future PRs that surface this data to the user (#6) will build on top
// of this contract. If those PRs ever need finer-grained data, they
// must extend the snapshot type explicitly and update the privacy
// guarantees here.

import Foundation
import KeyPathCore

/// One day's aggregate sample. Used by the insights chart to draw a
/// line over the past 30 days; never used to reconstruct individual
/// keystrokes.
///
/// Stored as ISO date strings (YYYY-MM-DD) rather than `Date` so the
/// JSON file remains human-readable and timezone-stable.
struct KindaVimDailySnapshot: Codable, Equatable, Sendable {
    /// ISO date for the local-day this sample covers ("2026-04-25").
    var date: String

    /// Count of arrow / Page / Home / End presses recorded today.
    var nonVimNavigationCount: Int = 0

    /// Count of `h`/`j`/`k`/`l` presses recorded today.
    var hjklCount: Int = 0

    /// Vocabulary size at end-of-day: how many commands had crossed
    /// the fluency threshold (≥10 lifetime presses) by today.
    var vocabularySize: Int = 0

    /// Seconds spent in `.normal` mode today.
    var normalDwellSeconds: TimeInterval = 0

    /// Seconds spent in `.insert` mode today.
    var insertDwellSeconds: TimeInterval = 0
}

/// Aggregate usage counters. Pure values — safe to send across actor
/// boundaries, safe to serialise.
struct KindaVimTelemetrySnapshot: Codable, Equatable, Sendable {
    /// Counter for every vim command the user has pressed (key →
    /// total press count). Keys are stored in lowercased physical-key
    /// form ("h", "j", "0", "slash", etc.) — same vocabulary as
    /// `OverlayKeyboardView.keyCodeToKanataName`.
    var commandFrequency: [String: Int] = [:]

    /// Counter for non-vim navigation keys: arrows, Home, End,
    /// Page Up/Down. Recorded regardless of mode (whereas
    /// `commandFrequency` is gated to normal/visual). Powers the
    /// arrow-reliance headline metric.
    var nonVimNavigationFrequency: [String: Int] = [:]

    /// Cumulative seconds spent in each mode. Insert is included so
    /// "what fraction of time am I actually using vim modes?" is a
    /// derivable insight.
    var modeDwellSeconds: [String: TimeInterval] = [:]

    /// Strategy distribution. Counts how many times the user's
    /// frontmost-app strategy resolved to each value, sampled on every
    /// app-switch. Useful for "you're using the Keyboard fallback most
    /// of the time" insight.
    var strategySamples: [String: Int] = [:]

    /// Operator-pending sequences started; how many completed (flipped
    /// to normal/visual after picking a motion) vs cancelled (flipped
    /// to insert or back to the same mode without a motion). Useful as
    /// a learning-progress signal.
    var operatorPendingCompleted: Int = 0
    var operatorPendingCancelled: Int = 0

    /// One entry per local-day with activity. Capped at the most
    /// recent 90 days during writes so the file size stays bounded.
    var dailySnapshots: [KindaVimDailySnapshot] = []

    /// First time we wrote any data to the file. Used in PR #6's
    /// "since you started using vim" framing — never a timestamp on an
    /// individual event.
    var firstRecordedAt: Date?

    /// Last write timestamp. Lets PR #6 surface "last active" without
    /// retaining individual events.
    var lastUpdatedAt: Date?

    // MARK: - Schema migration

    /// Custom decoder so files written by earlier versions (which
    /// didn't have `nonVimNavigationFrequency` or `dailySnapshots`)
    /// decode cleanly with empty defaults. New fields appended here
    /// should default-initialise the same way to preserve forward-
    /// compat for users on stale builds.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        commandFrequency = try container.decodeIfPresent([String: Int].self, forKey: .commandFrequency) ?? [:]
        nonVimNavigationFrequency = try container.decodeIfPresent([String: Int].self, forKey: .nonVimNavigationFrequency) ?? [:]
        modeDwellSeconds = try container.decodeIfPresent([String: TimeInterval].self, forKey: .modeDwellSeconds) ?? [:]
        strategySamples = try container.decodeIfPresent([String: Int].self, forKey: .strategySamples) ?? [:]
        operatorPendingCompleted = try container.decodeIfPresent(Int.self, forKey: .operatorPendingCompleted) ?? 0
        operatorPendingCancelled = try container.decodeIfPresent(Int.self, forKey: .operatorPendingCancelled) ?? 0
        dailySnapshots = try container.decodeIfPresent([KindaVimDailySnapshot].self, forKey: .dailySnapshots) ?? []
        firstRecordedAt = try container.decodeIfPresent(Date.self, forKey: .firstRecordedAt)
        lastUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .lastUpdatedAt)
    }

    init() {}
}

@MainActor
final class KindaVimTelemetryStore {
    static let shared = KindaVimTelemetryStore()

    /// `@AppStorage`-equivalent key — read directly so we don't depend
    /// on a SwiftUI view to gate writes. Settings UI flips this same
    /// `UserDefaults` key.
    static let optInKey = "kindaVim.telemetryEnabled"

    static var defaultFileURL: URL {
        let support = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("KeyPath", isDirectory: true)
        return support.appendingPathComponent("kindavim-telemetry.json")
    }

    private let fileURL: URL
    private let userDefaults: UserDefaults
    private var cached: KindaVimTelemetrySnapshot?

    /// Debounced disk-flush. Mutations bump `pendingWrite = true`; the
    /// active flush task waits `flushInterval` seconds, then writes the
    /// cached snapshot to disk. This keeps a heavy typist (~100
    /// keypresses/minute) from generating ~5 MB/minute of disk traffic
    /// while preserving JSON's audit-friendliness.
    ///
    /// Worst-case data loss on a crash is bounded to `flushInterval`
    /// seconds of counter increments — fine for aggregate telemetry.
    private let flushInterval: TimeInterval
    private var pendingWrite: Bool = false
    private var flushTask: Task<Void, Never>?

    init(
        fileURL: URL = KindaVimTelemetryStore.defaultFileURL,
        userDefaults: UserDefaults = .standard,
        flushInterval: TimeInterval = 5
    ) {
        self.fileURL = fileURL
        self.userDefaults = userDefaults
        self.flushInterval = flushInterval
    }

    deinit {
        flushTask?.cancel()
        // No final flush from deinit — the @MainActor restriction makes
        // it impractical, and the `flushNow()` API + app-deactivation
        // hook (TODO in a follow-up) covers correctness for the cases
        // that matter (Pack Detail viewing, app quit).
    }

    // MARK: - Opt-in gate

    /// Whether the user has explicitly opted in. Default off.
    var isEnabled: Bool {
        userDefaults.bool(forKey: Self.optInKey)
    }

    // MARK: - Recording

    func recordCommand(_ key: String) {
        guard isEnabled, !key.isEmpty else { return }
        let lower = key.lowercased()
        mutate { snapshot in
            snapshot.commandFrequency[lower, default: 0] += 1
            // Daily-bucket: hjkl drive the headline metric's denominator.
            if Self.hjklKeys.contains(lower) {
                Self.upsertToday(in: &snapshot.dailySnapshots) { day in
                    day.hjklCount += 1
                }
            }
            // Daily-bucket: vocabulary size = unique commands ≥ fluency
            // threshold. Recompute on every cumulative bump (cheap; the
            // frequency dict is bounded by kindaVim's small command set).
            let vocab = Self.vocabularySize(in: snapshot.commandFrequency)
            Self.upsertToday(in: &snapshot.dailySnapshots) { day in
                day.vocabularySize = vocab
            }
        }
    }

    /// Record a non-vim navigation key (arrow, Page Up/Down, Home, End).
    /// Recorded regardless of mode — these indicate the user is
    /// reaching outside vim's grammar even though they have the pack on.
    func recordNonVimNavigation(_ key: String) {
        guard isEnabled, !key.isEmpty else { return }
        let lower = key.lowercased()
        mutate { snapshot in
            snapshot.nonVimNavigationFrequency[lower, default: 0] += 1
            Self.upsertToday(in: &snapshot.dailySnapshots) { day in
                day.nonVimNavigationCount += 1
            }
        }
    }

    func recordModeDwell(_ mode: String, duration: TimeInterval) {
        guard isEnabled, duration > 0 else { return }
        mutate { snapshot in
            snapshot.modeDwellSeconds[mode, default: 0] += duration
            // Daily-bucket: only normal + insert are headline-relevant;
            // visual / op-pending fold into the lifetime counters but
            // don't get their own daily series.
            switch mode {
            case "normal":
                Self.upsertToday(in: &snapshot.dailySnapshots) { day in
                    day.normalDwellSeconds += duration
                }
            case "insert":
                Self.upsertToday(in: &snapshot.dailySnapshots) { day in
                    day.insertDwellSeconds += duration
                }
            default:
                break
            }
        }
    }

    func recordStrategySample(_ strategy: String) {
        guard isEnabled, !strategy.isEmpty else { return }
        mutate { snapshot in
            snapshot.strategySamples[strategy, default: 0] += 1
        }
    }

    func recordOperatorPendingExit(completed: Bool) {
        guard isEnabled else { return }
        mutate { snapshot in
            if completed {
                snapshot.operatorPendingCompleted += 1
            } else {
                snapshot.operatorPendingCancelled += 1
            }
        }
    }

    // MARK: - Snapshot + clear

    /// Read the current snapshot. Returns an empty snapshot if the
    /// file is absent or unreadable — never throws to the caller.
    func loadSnapshot() -> KindaVimTelemetrySnapshot {
        if let cached { return cached }
        let snapshot = readFromDisk() ?? KindaVimTelemetrySnapshot()
        cached = snapshot
        return snapshot
    }

    /// Wipe the file and the in-memory cache. Intentional: the user
    /// asked us to forget their data, so we forget it.
    func clearAll() {
        flushTask?.cancel()
        flushTask = nil
        pendingWrite = false
        cached = nil
        try? FileManager.default.removeItem(at: fileURL)
        AppLogger.shared.log("🧹 [KindaVimTelemetry] Cleared all usage data")
    }

    /// Force any pending writes to disk synchronously. Callers (Pack
    /// Detail open, app deactivation) use this to make sure the user
    /// sees fresh data the moment they look at it. Tests use it to
    /// assert post-write file contents without waiting on the timer.
    func flushNow() {
        flushTask?.cancel()
        flushTask = nil
        guard pendingWrite, let snapshot = cached else { return }
        pendingWrite = false
        writeToDisk(snapshot)
    }

    // MARK: - Internals

    private func mutate(_ body: (inout KindaVimTelemetrySnapshot) -> Void) {
        var snapshot = loadSnapshot()
        let now = Date()
        if snapshot.firstRecordedAt == nil {
            snapshot.firstRecordedAt = now
        }
        snapshot.lastUpdatedAt = now
        body(&snapshot)
        // Bound the daily-snapshots history. The chart only ever needs
        // the most recent 30 days; retaining 90 leaves headroom for
        // retroactive recomputation if we add new derived series later.
        let cap = 90
        if snapshot.dailySnapshots.count > cap {
            snapshot.dailySnapshots.removeFirst(snapshot.dailySnapshots.count - cap)
        }
        cached = snapshot
        pendingWrite = true
        scheduleDebouncedFlush()
    }

    private func scheduleDebouncedFlush() {
        guard flushTask == nil else { return }  // already armed
        let delay = flushInterval
        flushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.flushNow()
        }
    }

    // MARK: - Daily-bucket helpers

    private static let hjklKeys: Set<String> = ["h", "j", "k", "l"]

    /// Fluency threshold — a command counts toward "vocabulary size"
    /// once the user has pressed it at least this many times. Mirrors
    /// the `Fluent` mastery tier in the insights UI.
    static let fluencyThreshold = 10

    private static func vocabularySize(in frequencies: [String: Int]) -> Int {
        frequencies.values.filter { $0 >= fluencyThreshold }.count
    }

    /// Find or append today's daily snapshot and apply the mutation.
    /// Date format is `YYYY-MM-DD` in the user's local timezone — same
    /// boundary as the user's notion of "today."
    private static func upsertToday(
        in snapshots: inout [KindaVimDailySnapshot],
        body: (inout KindaVimDailySnapshot) -> Void
    ) {
        let today = Self.localDateString(for: Date())
        if var last = snapshots.last, last.date == today {
            body(&last)
            snapshots[snapshots.count - 1] = last
        } else {
            var fresh = KindaVimDailySnapshot(date: today)
            body(&fresh)
            snapshots.append(fresh)
        }
    }

    static func localDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    private func readFromDisk() -> KindaVimTelemetrySnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(KindaVimTelemetrySnapshot.self, from: data)
    }

    private func writeToDisk(_ snapshot: KindaVimTelemetrySnapshot) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
