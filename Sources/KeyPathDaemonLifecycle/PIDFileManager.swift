import Foundation
import KeyPathCore

/// Simple PID file manager for tracking kanata process ownership
/// Replaces complex regex-based ownership detection with deterministic PID tracking
/// Uses static methods for simple, stateless file operations
public enum PIDFileManager {
    // MARK: - Constants

    private static let pidFileName = "kanata.pid"
    private static let pidDirectory = "\(NSHomeDirectory())/Library/Application Support/KeyPath"

    public static var pidFilePath: String {
        "\(pidDirectory)/\(pidFileName)"
    }

    // MARK: - PID File Structure

    public struct PIDRecord: Codable, Sendable {
        public let pid: Int32
        public let startTime: Date
        public let command: String
        public let bundleIdentifier: String

        public var age: TimeInterval { Date().timeIntervalSince(startTime) }
        public var isStale: Bool { age > 3600 }
    }

    // MARK: - Public API

    /// Write PID file when starting kanata
    public static func writePID(_ pid: pid_t, command: String) throws {
        ensureDirectoryExists()

        let record = PIDRecord(
            pid: pid,
            startTime: Date(),
            command: command,
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.keypath.KeyPath"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(record)

        try data.write(to: URL(fileURLWithPath: pidFilePath))
        AppLogger.shared.log("✅ [PIDFile] Written PID \(pid) to \(pidFilePath)")
    }

    /// Read PID file if it exists
    public static func readPID() -> PIDRecord? {
        guard FileManager.default.fileExists(atPath: pidFilePath) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: pidFilePath))
            let decoder = JSONDecoder()
            let record = try decoder.decode(PIDRecord.self, from: data)
            AppLogger.shared.log(
                "📖 [PIDFile] Read PID \(record.pid) from file (age: \(Int(record.age))s)")
            return record
        } catch {
            AppLogger.shared.log("❌ [PIDFile] Failed to read PID file: \(error)")
            // Corrupted PID file, remove it
            try? removePID()
            return nil
        }
    }

    /// Remove PID file
    public static func removePID() throws {
        guard FileManager.default.fileExists(atPath: pidFilePath) else {
            return
        }

        try FileManager.default.removeItem(atPath: pidFilePath)
        AppLogger.shared.log("🗑️ [PIDFile] Removed PID file")
    }

    /// Check if a process with given PID is still running
    public static func isProcessRunning(pid: pid_t) -> Bool {
        let result = kill(pid, 0)
        return result == 0
    }

    /// Check if we own the currently running kanata process
    public static func checkOwnership() -> (owned: Bool, pid: pid_t?) {
        guard let record = readPID() else {
            AppLogger.shared.log("ℹ️ [PIDFile] No PID file found - no owned process")
            return (false, nil)
        }

        // Check if the process is still running
        if !isProcessRunning(pid: record.pid) {
            AppLogger.shared.log("💀 [PIDFile] Process \(record.pid) is dead - cleaning up PID file")
            try? removePID()
            return (false, nil)
        }

        // Check if PID is stale (app crash scenario)
        if record.isStale {
            AppLogger.shared.log(
                "⏰ [PIDFile] PID \(record.pid) is stale (age: \(Int(record.age))s) - considering orphaned")
            return (false, record.pid)
        }

        // Process is running and PID file is recent - we own it
        AppLogger.shared.log("✅ [PIDFile] Process \(record.pid) is owned by KeyPath")
        return (true, record.pid)
    }

    /// Kill orphaned process and clean up
    public static func killOrphanedProcess() async {
        guard let record = readPID() else { return }

        if isProcessRunning(pid: record.pid) {
            AppLogger.shared.log("💀 [PIDFile] Killing orphaned process \(record.pid)")

            // Try graceful termination first
            kill(record.pid, SIGTERM)

            // Wait a moment
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            // Force kill if still running
            if isProcessRunning(pid: record.pid) {
                kill(record.pid, SIGKILL)
            }
        }

        try? removePID()
    }

    // MARK: - Private Helpers
    private static func ensureDirectoryExists() {
        if !FileManager.default.fileExists(atPath: pidDirectory) {
            try? FileManager.default.createDirectory(
                atPath: pidDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )
        }
    }
}



