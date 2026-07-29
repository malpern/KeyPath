import Foundation

public struct SystemResourceSample: Codable, Equatable, Sendable {
    public let timestampNs: UInt64
    public let cpuUtilization: Double?
    public let loadAveragePerCore: Double
    public let availableMemoryBytes: UInt64
    public let physicalMemoryBytes: UInt64
    public let threadCount: Int
    public let logicalProcessorCount: Int
    public let memoryPressureLevel: Int
    public let thermalState: String

    public init(
        timestampNs: UInt64,
        cpuUtilization: Double?,
        loadAveragePerCore: Double,
        availableMemoryBytes: UInt64,
        physicalMemoryBytes: UInt64,
        threadCount: Int,
        logicalProcessorCount: Int,
        memoryPressureLevel: Int,
        thermalState: String
    ) {
        self.timestampNs = timestampNs
        self.cpuUtilization = cpuUtilization
        self.loadAveragePerCore = loadAveragePerCore
        self.availableMemoryBytes = availableMemoryBytes
        self.physicalMemoryBytes = physicalMemoryBytes
        self.threadCount = threadCount
        self.logicalProcessorCount = logicalProcessorCount
        self.memoryPressureLevel = memoryPressureLevel
        self.thermalState = thermalState
    }
}

public enum SystemReadinessState: String, Codable, Sendable {
    case calibrating
    case ready
    case waiting
}

public struct SystemReadinessAssessment: Codable, Equatable, Sendable {
    public let state: SystemReadinessState
    public let canProceed: Bool
    public let summary: String
    public let detail: String
    public let issues: [String]
    public let suggestions: [String]
    public let stableSamples: Int
    public let requiredStableSamples: Int

    public static let calibrating = SystemReadinessAssessment(
        state: .calibrating,
        canProceed: false,
        summary: "Measuring CPU, load, memory, and temperature",
        detail: "Keep this window open; readiness normally takes three seconds.",
        issues: [],
        suggestions: ["Wait a few seconds while the Jig establishes a stable baseline."],
        stableSamples: 0,
        requiredStableSamples: 3
    )
}

public enum SystemReadinessModel {
    public static let requiredStableSamples = 3
    private static let maximumCPUUtilization = 0.80
    private static let maximumLoadPerCore = 0.90
    private static let minimumAvailableMemoryBytes: UInt64 = 2 * 1024 * 1024 * 1024
    private static let maximumThreadsPerCore = 900

    public static func resolve(
        samples: [SystemResourceSample],
        requiredSamples: Int = requiredStableSamples
    ) -> SystemReadinessAssessment {
        guard requiredSamples > 0, let latest = samples.last else { return .calibrating }
        let summary = metricSummary(latest)
        let latestIssues = issues(for: latest)
        if !latestIssues.isEmpty {
            return SystemReadinessAssessment(
                state: .waiting,
                canProceed: false,
                summary: summary,
                detail: latestIssues.joined(separator: " · "),
                issues: latestIssues,
                suggestions: suggestions(for: latestIssues),
                stableSamples: 0,
                requiredStableSamples: requiredSamples
            )
        }

        let recent = Array(samples.suffix(requiredSamples))
        let cleanCount = recent.reversed().prefix { issues(for: $0).isEmpty }.count
        guard recent.count == requiredSamples, cleanCount == requiredSamples else {
            return SystemReadinessAssessment(
                state: .calibrating,
                canProceed: false,
                summary: summary,
                detail: "Conditions are improving; confirming a stable window (\(cleanCount)/\(requiredSamples)).",
                issues: [],
                suggestions: ["Wait a few seconds; the Jig will recheck automatically."],
                stableSamples: cleanCount,
                requiredStableSamples: requiredSamples
            )
        }

        return SystemReadinessAssessment(
            state: .ready,
            canProceed: true,
            summary: summary,
            detail: "Resources have stayed within the capture envelope for \(requiredSamples) checks.",
            issues: [],
            suggestions: [],
            stableSamples: requiredSamples,
            requiredStableSamples: requiredSamples
        )
    }

    private static func issues(for sample: SystemResourceSample) -> [String] {
        var issues: [String] = []
        if let cpu = sample.cpuUtilization, cpu >= maximumCPUUtilization {
            issues.append("CPU \(percent(cpu)) (limit \(percent(maximumCPUUtilization)))")
        }
        if sample.loadAveragePerCore >= maximumLoadPerCore {
            issues.append(String(
                format: "competing work %.1f×/core (limit %.1f×)",
                sample.loadAveragePerCore, maximumLoadPerCore
            ))
        }
        let proportionalMemoryFloor = UInt64(Double(sample.physicalMemoryBytes) * 0.08)
        let memoryFloor = max(minimumAvailableMemoryBytes, proportionalMemoryFloor)
        if sample.availableMemoryBytes < memoryFloor {
            issues.append("memory \(gigabytes(sample.availableMemoryBytes)) available (need \(gigabytes(memoryFloor)))")
        }
        if sample.memoryPressureLevel > 1 {
            issues.append("macOS memory pressure elevated")
        }
        if sample.thermalState == "serious" || sample.thermalState == "critical" {
            issues.append("thermal state is \(sample.thermalState)")
        }
        let processorCount = max(1, sample.logicalProcessorCount)
        if sample.threadCount > processorCount * maximumThreadsPerCore {
            issues.append("system thread inventory is unusually high (\(sample.threadCount))")
        }
        return issues
    }

    private static func suggestions(for issues: [String]) -> [String] {
        var result: [String] = []
        if issues.contains(where: { $0.contains("CPU") || $0.contains("competing work") }) {
            result.append("Pause builds, exports, VMs, or other CPU-heavy jobs.")
        }
        if issues.contains(where: { $0.contains("memory") || $0.contains("thread inventory") }) {
            result.append("Close unused apps or VMs to free memory and background workers.")
        }
        if issues.contains(where: { $0.contains("thermal") }) {
            result.append("Let the Mac cool and keep its vents clear before retrying.")
        }
        result.append("The Jig will recheck automatically; no restart is required.")
        return result
    }

    private static func metricSummary(_ sample: SystemResourceSample) -> String {
        let cpu = sample.cpuUtilization.map { "\(percent($0)) CPU" } ?? "sampling CPU"
        return String(
            format: "%@ · load %.1f× · %@ available",
            cpu, sample.loadAveragePerCore, gigabytes(sample.availableMemoryBytes)
        )
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }
}
