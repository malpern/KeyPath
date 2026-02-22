import Foundation
import KeyPathCore
import Observation

/// Tracks KindaVim's environment.json and exposes the current mode for UI integrations.
///
/// File source:
/// `~/Library/Application Support/kindaVim/environment.json`
@MainActor
@Observable
final class KindaVimEnvironmentService {
    enum Mode: String, Equatable {
        case insert
        case normal
        case visual
        case operatorPending
        case unknown

        var displayName: String {
            switch self {
            case .insert: "Insert"
            case .normal: "Normal"
            case .visual: "Visual"
            case .operatorPending: "Operator Pending"
            case .unknown: "Unknown"
            }
        }
    }

    struct EnvironmentPayload: Codable, Equatable {
        let mode: String?
    }

    static let shared = KindaVimEnvironmentService()

    static var defaultEnvironmentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("kindaVim")
            .appendingPathComponent("environment.json")
    }

    public private(set) var isMonitoring = false
    public private(set) var isEnvironmentFilePresent = false
    public private(set) var rawModeValue: String?
    public private(set) var currentMode: Mode = .unknown
    public private(set) var lastUpdatedAt: Date?

    var modeDisplayName: String? {
        guard currentMode != .unknown else { return nil }
        return currentMode.displayName
    }

    @ObservationIgnored private var monitoringCount = 0
    @ObservationIgnored private var fileWatcher: ConfigFileWatcher?
    @ObservationIgnored private let environmentURL: URL

    private init(environmentURL: URL = KindaVimEnvironmentService.defaultEnvironmentURL) {
        self.environmentURL = environmentURL
        refresh()
    }

    func startMonitoring() {
        monitoringCount += 1
        guard monitoringCount == 1 else { return }

        let watcher = ConfigFileWatcher()
        watcher.startWatching(path: environmentURL.path) { [weak self] in
            self?.refresh()
        }
        fileWatcher = watcher
        isMonitoring = true
        refresh()

        AppLogger.shared.log("👀 [KindaVimEnv] Started monitoring \(environmentURL.path)")
    }

    func stopMonitoring() {
        guard monitoringCount > 0 else { return }
        monitoringCount -= 1
        guard monitoringCount == 0 else { return }

        fileWatcher?.stopWatching()
        fileWatcher = nil
        isMonitoring = false

        AppLogger.shared.log("🛑 [KindaVimEnv] Stopped monitoring")
    }

    func refresh() {
        let fileExists = FileManager.default.fileExists(atPath: environmentURL.path)
        isEnvironmentFilePresent = fileExists

        guard fileExists else {
            rawModeValue = nil
            currentMode = .unknown
            return
        }

        do {
            let data = try Data(contentsOf: environmentURL)
            let parsedRawMode = Self.parseMode(from: data)
            let parsedMode = Self.normalizedMode(from: parsedRawMode)
            let modeChanged = parsedMode != currentMode

            rawModeValue = parsedRawMode
            currentMode = parsedMode
            lastUpdatedAt = Date()

            if modeChanged {
                AppLogger.shared.log("🧭 [KindaVimEnv] Mode changed to \(parsedMode.displayName)")
            }
        } catch {
            AppLogger.shared.log("⚠️ [KindaVimEnv] Failed to read environment.json: \(error.localizedDescription)")
            rawModeValue = nil
            currentMode = .unknown
        }
    }

    static func parseMode(from data: Data) -> String? {
        guard let payload = try? JSONDecoder().decode(EnvironmentPayload.self, from: data) else {
            return nil
        }
        return payload.mode
    }

    static func normalizedMode(from rawMode: String?) -> Mode {
        guard let rawMode else { return .unknown }

        let normalized = rawMode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        return switch normalized {
        case "insert":
            Mode.insert
        case "normal":
            Mode.normal
        case "visual":
            Mode.visual
        case "operator_pending", "operatorpending", "operator":
            Mode.operatorPending
        default:
            Mode.unknown
        }
    }
}
