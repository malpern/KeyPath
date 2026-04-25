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

/// Aggregate usage counters. Pure values — safe to send across actor
/// boundaries, safe to serialise.
struct KindaVimTelemetrySnapshot: Codable, Equatable, Sendable {
    /// Counter for every vim command the user has pressed (key →
    /// total press count). Keys are stored in lowercased physical-key
    /// form ("h", "j", "0", "slash", etc.) — same vocabulary as
    /// `OverlayKeyboardView.keyCodeToKanataName`.
    var commandFrequency: [String: Int] = [:]

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

    /// First time we wrote any data to the file. Used in PR #6's
    /// "since you started using vim" framing — never a timestamp on an
    /// individual event.
    var firstRecordedAt: Date?

    /// Last write timestamp. Lets PR #6 surface "last active" without
    /// retaining individual events.
    var lastUpdatedAt: Date?
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

    init(
        fileURL: URL = KindaVimTelemetryStore.defaultFileURL,
        userDefaults: UserDefaults = .standard
    ) {
        self.fileURL = fileURL
        self.userDefaults = userDefaults
    }

    // MARK: - Opt-in gate

    /// Whether the user has explicitly opted in. Default off.
    var isEnabled: Bool {
        userDefaults.bool(forKey: Self.optInKey)
    }

    // MARK: - Recording

    func recordCommand(_ key: String) {
        guard isEnabled, !key.isEmpty else { return }
        mutate { snapshot in
            snapshot.commandFrequency[key.lowercased(), default: 0] += 1
        }
    }

    func recordModeDwell(_ mode: String, duration: TimeInterval) {
        guard isEnabled, duration > 0 else { return }
        mutate { snapshot in
            snapshot.modeDwellSeconds[mode, default: 0] += duration
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
        cached = nil
        try? FileManager.default.removeItem(at: fileURL)
        AppLogger.shared.log("🧹 [KindaVimTelemetry] Cleared all usage data")
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
        cached = snapshot
        writeToDisk(snapshot)
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
