#if os(macOS)

    import XCTest

    @testable import KeyPath

    final class BatteryMonitorTests: XCTestCase {
        func testBatteryMonitorEmitsReadings() async {
            let readings = [
                BatteryReading(level: 0.52, isCharging: false, timestamp: Date()),
                BatteryReading(level: 0.41, isCharging: false, timestamp: Date()),
                BatteryReading(level: 0.62, isCharging: true, timestamp: Date())
            ]

            let provider = StubBatteryProvider(readings: readings)
            // Use a poll interval that respects the minimum (1.0 second)
            let monitor = BatteryMonitor(pollInterval: 0.5, provider: provider)

            let expectation = expectation(description: "Battery readings delivered")
            // BatteryMonitor calls handler immediately, then waits for pollInterval
            // So we expect at least 2 readings (immediate + after first poll)
            expectation.expectedFulfillmentCount = 2

            final class CapturedReadings: @unchecked Sendable {
                var values: [BatteryReading] = []
            }
            let captured = CapturedReadings()

            monitor.start { reading in
                guard let reading else { return }
                captured.values.append(reading)
                expectation.fulfill()
            }

            // Wait longer to account for poll interval clamping to 1.0 second
            await fulfillment(of: [expectation], timeout: 2.5)
            monitor.stop()

            // Should have at least 2 readings (immediate + after first poll)
            XCTAssertGreaterThanOrEqual(captured.values.count, 2, "Should receive at least 2 readings")

            // Verify the readings match what we provided (may be fewer due to timing)
            let minCount = min(captured.values.count, readings.count)
            for i in 0 ..< minCount {
                XCTAssertEqual(captured.values[i].level, readings[i].level, accuracy: 0.0001)
                XCTAssertEqual(captured.values[i].isCharging, readings[i].isCharging)
            }

            // Provider should have been called at least as many times as readings received
            XCTAssertGreaterThanOrEqual(provider.callCount, captured.values.count)
        }

        func testBatteryMonitorStopPreventsAdditionalSamples() async throws {
            let readings = Array(repeating: BatteryReading(level: 0.45, isCharging: false, timestamp: Date()), count: 6)
            let provider = StubBatteryProvider(readings: readings)
            let monitor = BatteryMonitor(pollInterval: 0.5, provider: provider)

            let expectation = expectation(description: "Initial readings")
            // Expect at least 1 reading (immediate call)
            expectation.expectedFulfillmentCount = 1

            monitor.start { reading in
                if reading != nil {
                    expectation.fulfill()
                }
            }

            // Wait for at least one reading (immediate call)
            await fulfillment(of: [expectation], timeout: 0.5)

            monitor.stop()
            let readsAfterStop = provider.callCount

            // Wait longer to ensure no additional reads happen
            try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

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
