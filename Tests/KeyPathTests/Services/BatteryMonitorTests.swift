#if os(macOS)

import XCTest

@testable import KeyPath

final class BatteryMonitorTests: XCTestCase {
    func testBatteryMonitorEmitsReadings() {
        let readings = [
            BatteryReading(level: 0.52, isCharging: false, timestamp: Date()),
            BatteryReading(level: 0.41, isCharging: false, timestamp: Date()),
            BatteryReading(level: 0.62, isCharging: true, timestamp: Date())
        ]

        let provider = StubBatteryProvider(readings: readings)
        let monitor = BatteryMonitor(pollInterval: 0.01, provider: provider)

        let expectation = expectation(description: "Battery readings delivered")
        expectation.expectedFulfillmentCount = readings.count

        var captured: [BatteryReading] = []

        monitor.start { reading in
            guard let reading else { return }
            captured.append(reading)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
        monitor.stop()

        XCTAssertEqual(captured.count, readings.count)
        zip(captured, readings).forEach { capturedReading, expectedReading in
            XCTAssertEqual(capturedReading.level, expectedReading.level, accuracy: 0.0001)
            XCTAssertEqual(capturedReading.isCharging, expectedReading.isCharging)
        }
        XCTAssertGreaterThanOrEqual(provider.callCount, readings.count)
    }

    func testBatteryMonitorStopPreventsAdditionalSamples() async throws {
        let readings = Array(repeating: BatteryReading(level: 0.45, isCharging: false, timestamp: Date()), count: 6)
        let provider = StubBatteryProvider(readings: readings)
        let monitor = BatteryMonitor(pollInterval: 0.01, provider: provider)

        let expectation = expectation(description: "Initial readings")
        expectation.expectedFulfillmentCount = 3

        monitor.start { reading in
            if reading != nil {
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1.0)

        monitor.stop()
        let readsAfterStop = provider.callCount

        try await Task.sleep(nanoseconds: 50_000_000) // 50ms for background task to cancel

        XCTAssertEqual(provider.callCount, readsAfterStop, "No additional samples should be taken after stop()")
    }
}

private final class StubBatteryProvider: BatteryStatusProviding {
    private let readings: [BatteryReading]
    private var index = 0
    private(set) var callCount = 0

    init(readings: [BatteryReading]) {
        self.readings = readings
    }

    func currentStatus() -> BatteryReading? {
        defer { callCount += 1 }
        guard index < readings.count else { return nil }
        let value = readings[index]
        index += 1
        return value
    }
}

#endif
