import HIDCaptureCore
import XCTest

final class SystemReadinessTests: XCTestCase {
    private func sample(
        at timestamp: UInt64,
        cpu: Double? = 0.25,
        load: Double = 0.35,
        availableGB: UInt64 = 8,
        pressure: Int = 1,
        thermal: String = "nominal",
        threads: Int = 3_000
    ) -> SystemResourceSample {
        SystemResourceSample(
            timestampNs: timestamp,
            cpuUtilization: cpu,
            loadAveragePerCore: load,
            availableMemoryBytes: availableGB * 1_024 * 1_024 * 1_024,
            physicalMemoryBytes: 32 * 1_024 * 1_024 * 1_024,
            threadCount: threads,
            logicalProcessorCount: 10,
            memoryPressureLevel: pressure,
            thermalState: thermal
        )
    }

    func testRequiresStableWindowBeforeProceeding() {
        let first = SystemReadinessModel.resolve(samples: [sample(at: 1)])
        XCTAssertEqual(first.state, .calibrating)
        XCTAssertFalse(first.canProceed)

        let ready = SystemReadinessModel.resolve(samples: [
            sample(at: 1), sample(at: 2), sample(at: 3),
        ])
        XCTAssertEqual(ready.state, .ready)
        XCTAssertTrue(ready.canProceed)
        XCTAssertEqual(ready.stableSamples, 3)
    }

    func testBusyCPUAndLoadFailWithActionableGuidance() {
        let assessment = SystemReadinessModel.resolve(samples: [
            sample(at: 1), sample(at: 2), sample(at: 3, cpu: 0.91, load: 1.4),
        ])
        XCTAssertEqual(assessment.state, .waiting)
        XCTAssertFalse(assessment.canProceed)
        XCTAssertTrue(assessment.issues.contains { $0.contains("CPU") })
        XCTAssertTrue(assessment.issues.contains { $0.contains("competing work") })
        XCTAssertTrue(assessment.suggestions.contains { $0.contains("Pause builds") })
    }

    func testMemoryThermalAndThreadPressureFailClosed() {
        let assessment = SystemReadinessModel.resolve(samples: [sample(
            at: 1, availableGB: 1, pressure: 2, thermal: "serious", threads: 9_100
        )])
        XCTAssertFalse(assessment.canProceed)
        XCTAssertTrue(assessment.issues.contains { $0.contains("memory") && $0.contains("available") })
        XCTAssertTrue(assessment.issues.contains { $0.contains("memory pressure") })
        XCTAssertTrue(assessment.issues.contains { $0.contains("thermal") })
        XCTAssertTrue(assessment.issues.contains { $0.contains("thread inventory") })
    }

    func testRecentBusySampleMustAgeOutOfWindow() {
        let samples = [
            sample(at: 1, cpu: 0.95), sample(at: 2), sample(at: 3), sample(at: 4),
        ]
        XCTAssertTrue(SystemReadinessModel.resolve(samples: samples).canProceed)
        XCTAssertFalse(SystemReadinessModel.resolve(samples: Array(samples.dropLast())).canProceed)
    }
}
