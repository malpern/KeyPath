import Foundation
import KeyPathCore

/// Best-effort Full Disk Access detection for KeyPath.
///
/// Why this exists:
/// - KeyPath needs FDA primarily to *read the TCC databases* for Kanata permission verification (ADR-016).
/// - We must surface "not verified" (unknown) when FDA isn't granted, instead of showing a false green status.
///
/// Important constraints:
/// - This must only be used from the GUI app (user session).
/// - This is a heuristic check (file readability) and should remain best-effort + cached.
@MainActor
final class FullDiskAccessChecker {
    static let shared = FullDiskAccessChecker()

    private init() {}

    /// Test seam: override the probe result (used by unit tests).
    /// This must remain nil in production.
    nonisolated(unsafe) static var probeOverride: (() -> Bool)?

    private var cachedValue: Bool?
    private var lastCheckTime: Date?

    /// Keep this short; users may toggle FDA while the app is running.
    private let cacheTTL: TimeInterval = 10.0

    /// System TCC database path. Access is restricted unless the user grants Full Disk Access.
    /// We intentionally do NOT probe the user-scoped TCC database because it can create false positives.
    private let systemTCCPath = "/Library/Application Support/com.apple.TCC/TCC.db"

    func hasFullDiskAccess() -> Bool {
        if let lastCheckTime,
           let cachedValue,
           Date().timeIntervalSince(lastCheckTime) < cacheTTL {
            return cachedValue
        }
        return refresh()
    }

    /// Force a fresh probe (still best-effort).
    @discardableResult
    func refresh() -> Bool {
        let value = performFDACheck()
        cachedValue = value
        lastCheckTime = Date()
        return value
    }

    /// Allows wizard flows to eagerly update the cache when they detect FDA.
    func updateCachedValue(_ value: Bool) {
        cachedValue = value
        lastCheckTime = Date()
    }

    /// Clear cached state (primarily for tests).
    func resetCache() {
        cachedValue = nil
        lastCheckTime = nil
    }

    private func performFDACheck() -> Bool {
        if let override = Self.probeOverride {
            return override()
        }

        // Avoid any heavy or invasive probing. This is a lightweight "can we read system TCC.db" test.
        guard FileManager.default.isReadableFile(atPath: systemTCCPath) else {
            return false
        }

        // Try a minimal read; mappedIfSafe avoids copying large files.
        if let data = try? Data(contentsOf: URL(fileURLWithPath: systemTCCPath), options: .mappedIfSafe),
           data.count > 0 {
            return true
        }

        return false
    }
}
