import Foundation

/// Deletes KeyPath's own privacy row so macOS can create a fresh one.
///
/// macOS keeps one row per bundle ID and binds it to the code signature it first
/// saw. When another copy of KeyPath (an Apple Development build, an old copy in
/// the Trash) created the row, the installed Developer ID build reads as denied
/// while its switch shows on, and adding it again with + only updates that row.
/// Deleting the row is the only reliable fix (2026-11-08, the Air).
public enum PermissionRowReset {
    /// The `tccutil` service names for the rows KeyPath can ask to reset.
    public enum Service: String, Sendable {
        case accessibility = "Accessibility"
        case inputMonitoring = "ListenEvent"
    }

    public static let tccutilPath = "/usr/bin/tccutil"

    /// Arguments for `tccutil`, scoped to one service and to `bundleID` only.
    public static func arguments(for service: Service, bundleID: String) -> [String] {
        ["reset", service.rawValue, bundleID]
    }

    /// Resets the row for this app's own bundle ID. Returns false when the bundle ID
    /// is unknown or tccutil fails; never resets other apps' rows.
    public static func reset(
        _ service: Service,
        bundleID: String? = Bundle.main.bundleIdentifier,
        run: (String, [String]) throws -> Int32 = PermissionRowReset.runProcess
    ) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return (try? run(tccutilPath, arguments(for: service, bundleID: bundleID))) == 0
    }

    public static func runProcess(_ path: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
