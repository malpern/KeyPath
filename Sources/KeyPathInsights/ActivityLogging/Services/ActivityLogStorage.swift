import Foundation
import KeyPathCore

/// Handles encrypted file I/O for activity logs
/// Uses JSON Lines format with monthly file rotation
public actor ActivityLogStorage {
    // MARK: - Constants

    private static let directoryName = "ActivityLog"
    private static let filePrefix = "activity-"
    private static let fileExtension = ".enc"

    // MARK: - Properties

    private let encryption: ActivityLogEncryption
    private let baseDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // MARK: - Errors

    public enum StorageError: Error, LocalizedError {
        case directoryCreationFailed(Error)
        case writeFailed(Error)
        case readFailed(Error)
        case invalidFileFormat

        public var errorDescription: String? {
            switch self {
            case let .directoryCreationFailed(error):
                "Failed to create storage directory: \(error.localizedDescription)"
            case let .writeFailed(error):
                "Failed to write activity log: \(error.localizedDescription)"
            case let .readFailed(error):
                "Failed to read activity log: \(error.localizedDescription)"
            case .invalidFileFormat:
                "Invalid activity log file format"
            }
        }
    }

    // MARK: - Singleton

    public static let shared = ActivityLogStorage()

    private init() {
        encryption = ActivityLogEncryption.shared

        // Use ~/Library/Application Support/KeyPath/ActivityLog/
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        baseDirectory = appSupport
            .appendingPathComponent("KeyPath")
            .appendingPathComponent(Self.directoryName)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Public Interface

    /// Append events to the current month's log file
    public func append(_ events: [ActivityEvent]) async throws {
        guard !events.isEmpty else { return }

        try ensureDirectoryExists()

        let filePath = currentMonthFilePath()

        // Read existing events (if any)
        var allEvents = await (try? readEventsFromFile(filePath)) ?? []
        allEvents.append(contentsOf: events)

        // Write back encrypted
        try await writeEventsToFile(allEvents, path: filePath)

        AppLogger.shared.log(
            "📊 [ActivityLogStorage] Appended \(events.count) events (total: \(allEvents.count))"
        )
    }

    /// Read all events within a date range
    public func readEvents(from startDate: Date, to endDate: Date) async throws -> [ActivityEvent] {
        try ensureDirectoryExists()

        var allEvents: [ActivityEvent] = []

        // Get all encrypted log files
        let files = try FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "enc" }

        // Read each file and filter by date
        for file in files {
            if let events = try? await readEventsFromFile(file) {
                let filtered = events.filter { event in
                    event.timestamp >= startDate && event.timestamp <= endDate
                }
                allEvents.append(contentsOf: filtered)
            }
        }

        // Sort by timestamp
        return allEvents.sorted { $0.timestamp < $1.timestamp }
    }

    /// Read all events (for reporting)
    public func readAllEvents() async throws -> [ActivityEvent] {
        try ensureDirectoryExists()

        var allEvents: [ActivityEvent] = []

        let files = try FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "enc" }

        for file in files {
            if let events = try? await readEventsFromFile(file) {
                allEvents.append(contentsOf: events)
            }
        }

        return allEvents.sorted { $0.timestamp < $1.timestamp }
    }

    /// Get total storage size in bytes
    public func totalSize() async -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        return files.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    /// Get total event count
    public func totalEventCount() async -> Int {
        guard let events = try? await readAllEvents() else {
            return 0
        }
        return events.count
    }

    /// Clear all activity logs
    public func clearAll() async throws {
        guard FileManager.default.fileExists(atPath: baseDirectory.path) else {
            return
        }

        let files = try FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "enc" }

        for file in files {
            try FileManager.default.removeItem(at: file)
        }

        // Also delete the encryption key
        try await encryption.deleteKey()

        AppLogger.shared.log("📊 [ActivityLogStorage] Cleared all activity logs")
    }

    /// Check if any logs exist
    public func hasLogs() async -> Bool {
        guard FileManager.default.fileExists(atPath: baseDirectory.path) else {
            return false
        }

        let files = (try? FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "enc" }) ?? []

        return !files.isEmpty
    }

    // MARK: - Private Helpers

    private func ensureDirectoryExists() throws {
        guard !FileManager.default.fileExists(atPath: baseDirectory.path) else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: baseDirectory,
                withIntermediateDirectories: true
            )
            AppLogger.shared.log("📊 [ActivityLogStorage] Created directory: \(baseDirectory.path)")
        } catch {
            throw StorageError.directoryCreationFailed(error)
        }
    }

    private func currentMonthFilePath() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let monthString = formatter.string(from: Date())
        return baseDirectory.appendingPathComponent("\(Self.filePrefix)\(monthString)\(Self.fileExtension)")
    }

    private func readEventsFromFile(_ path: URL) async throws -> [ActivityEvent] {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return []
        }

        do {
            let encryptedData = try Data(contentsOf: path)
            let decryptedData = try await encryption.decrypt(encryptedData)

            // Parse JSON Lines format
            let jsonString = String(data: decryptedData, encoding: .utf8) ?? ""
            let lines = jsonString.components(separatedBy: .newlines).filter { !$0.isEmpty }

            return lines.compactMap { line in
                guard let lineData = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(ActivityEvent.self, from: lineData)
            }
        } catch {
            throw StorageError.readFailed(error)
        }
    }

    private func writeEventsToFile(_ events: [ActivityEvent], path: URL) async throws {
        do {
            // Convert to JSON Lines format
            let lines = try events.map { event in
                let data = try encoder.encode(event)
                return String(data: data, encoding: .utf8) ?? ""
            }
            let jsonLines = lines.joined(separator: "\n")

            guard let plainData = jsonLines.data(using: .utf8) else {
                throw StorageError.invalidFileFormat
            }

            let encryptedData = try await encryption.encrypt(plainData)
            try encryptedData.write(to: path, options: .atomic)
        } catch let error as StorageError {
            throw error
        } catch {
            throw StorageError.writeFailed(error)
        }
    }
}
