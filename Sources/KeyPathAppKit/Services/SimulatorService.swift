import Foundation
import KeyPathCore

/// Service for running keyboard simulations using the bundled kanata-simulator binary.
/// This actor provides an async interface to:
/// 1. Generate simulation input files from key tap sequences
/// 2. Invoke the kanata-simulator CLI with the user's config
/// 3. Parse JSON output into structured SimulationResult
actor SimulatorService {
    private let simulatorPath: String
    private let fileManager: FileManager

    init(
        simulatorPath: String? = nil,
        fileManager: FileManager = .default
    ) {
        self.simulatorPath = simulatorPath ?? WizardSystemPaths.bundledSimulatorPath
        self.fileManager = fileManager
    }

    // MARK: - Public API

    /// Run simulation with a sequence of key taps
    /// - Parameters:
    ///   - taps: Key taps to simulate (each tap = press + delay + release)
    ///   - configPath: Path to the kanata config file
    /// - Returns: Parsed simulation result with events, layers, and timing
    func simulate(
        taps: [SimulatorKeyTap],
        configPath: String
    ) async throws -> SimulationResult {
        guard FeatureFlags.simulatorAndVirtualKeysEnabled else {
            throw SimulatorError.featureDisabled
        }
        guard !taps.isEmpty else {
            return SimulationResult(events: [], finalLayer: nil, durationMs: 0)
        }

        // Verify simulator exists
        guard fileManager.fileExists(atPath: simulatorPath) else {
            throw SimulatorError.simulatorNotFound
        }

        // Verify config exists
        guard fileManager.fileExists(atPath: configPath) else {
            throw SimulatorError.configNotFound(configPath)
        }

        // 1. Generate sim.txt content
        let simContent = generateSimContent(from: taps)

        // 2. Write to temp file
        let tempDir = fileManager.temporaryDirectory
        let simFile = tempDir.appendingPathComponent("keypath-sim-\(UUID().uuidString).txt")
        try simContent.write(to: simFile, atomically: true, encoding: .utf8)
        defer { try? fileManager.removeItem(at: simFile) }

        // 3. Invoke simulator CLI
        let jsonData = try await runSimulator(
            configPath: configPath,
            simFilePath: simFile.path
        )

        // 4. Parse JSON output
        do {
            return try JSONDecoder().decode(SimulationResult.self, from: jsonData)
        } catch {
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "<binary>"
            throw SimulatorError.invalidJSON("Failed to parse: \(error.localizedDescription)\nOutput: \(jsonString.prefix(500))")
        }
    }

    /// Run simulation with raw sim.txt content (for testing)
    /// - Parameters:
    ///   - simContent: Raw simulation content (e.g., "d:a t:50 u:a")
    ///   - configPath: Path to the kanata config file
    ///   - startLayer: Optional layer name to start simulation in (uses --start-layer flag)
    func simulateRaw(
        simContent: String,
        configPath: String,
        startLayer: String? = nil
    ) async throws -> SimulationResult {
        guard FeatureFlags.simulatorAndVirtualKeysEnabled else {
            throw SimulatorError.featureDisabled
        }
        guard fileManager.fileExists(atPath: simulatorPath) else {
            throw SimulatorError.simulatorNotFound
        }

        let tempDir = fileManager.temporaryDirectory
        let simFile = tempDir.appendingPathComponent("keypath-sim-\(UUID().uuidString).txt")
        try simContent.write(to: simFile, atomically: true, encoding: .utf8)
        defer { try? fileManager.removeItem(at: simFile) }

        let jsonData = try await runSimulator(
            configPath: configPath,
            simFilePath: simFile.path,
            startLayer: startLayer
        )

        return try JSONDecoder().decode(SimulationResult.self, from: jsonData)
    }

    /// Run simulation with --key-mapping mode for direct input→output mapping
    /// This is the preferred method for building layer key mappings as it
    /// provides a clean structure without needing timestamp correlation.
    /// - Parameters:
    ///   - simContent: Raw simulation content (e.g., "d:a t:50 u:a d:b t:50 u:b")
    ///   - configPath: Path to the kanata config file
    ///   - startLayer: Layer name to get mappings for
    func simulateKeyMapping(
        simContent: String,
        configPath: String,
        startLayer: String
    ) async throws -> SimulatorKeyMappingResult {
        guard FeatureFlags.simulatorAndVirtualKeysEnabled else {
            throw SimulatorError.featureDisabled
        }
        guard fileManager.fileExists(atPath: simulatorPath) else {
            throw SimulatorError.simulatorNotFound
        }

        let tempDir = fileManager.temporaryDirectory
        let simFile = tempDir.appendingPathComponent("keypath-sim-\(UUID().uuidString).txt")
        try simContent.write(to: simFile, atomically: true, encoding: .utf8)
        defer { try? fileManager.removeItem(at: simFile) }

        let jsonData = try await runSimulator(
            configPath: configPath,
            simFilePath: simFile.path,
            startLayer: startLayer,
            keyMappingMode: true
        )

        return try JSONDecoder().decode(SimulatorKeyMappingResult.self, from: jsonData)
    }

    // MARK: - Sim Content Generation

    /// Generate sim.txt content from key taps
    /// Format: "d:key t:delay u:key" for each tap
    func generateSimContent(from taps: [SimulatorKeyTap]) -> String {
        taps.map { tap in
            // Each tap = press, wait, release
            "d:\(tap.kanataKey) t:\(tap.delayAfterMs) u:\(tap.kanataKey)"
        }.joined(separator: " ")
    }

    // MARK: - Process Execution

    private func runSimulator(
        configPath: String,
        simFilePath: String,
        startLayer: String? = nil,
        keyMappingMode: Bool = false
    ) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: simulatorPath)

        var args = ["-c", configPath, "-s", simFilePath]
        // Use --key-mapping for direct input→output mapping, otherwise --json for event timeline
        if keyMappingMode {
            args.append("--key-mapping")
        } else {
            args.append("--json")
        }
        if let layer = startLayer {
            args.append(contentsOf: ["--start-layer", layer])
        }
        process.arguments = args

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: data)
                } else {
                    let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                    continuation.resume(throwing: SimulatorError.processFailedWithCode(
                        Int(proc.terminationStatus),
                        errorOutput.isEmpty ? "No error output" : errorOutput
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Testing Support

extension SimulatorService {
    /// Create a service with a custom simulator path (for testing)
    static func forTesting(simulatorPath: String) -> SimulatorService {
        SimulatorService(simulatorPath: simulatorPath)
    }
}
