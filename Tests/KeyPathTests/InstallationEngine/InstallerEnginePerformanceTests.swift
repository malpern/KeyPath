@testable import KeyPathAppKit
import XCTest

@MainActor
final class InstallerEnginePerformanceTests: XCTestCase {
    func testInspectSystemPerformance() async {
        let engine = InstallerEngine()

        // Warm up
        _ = await engine.inspectSystem()

        let iterations = 5
        var totalTime: TimeInterval = 0

        for _ in 0 ..< iterations {
            let start = Date()
            _ = await engine.inspectSystem()
            let duration = Date().timeIntervalSince(start)
            totalTime += duration
        }

        let averageTime = totalTime / Double(iterations)
        print("Average inspectSystem() time: \(averageTime) seconds")

        // Assert that it's reasonably fast (e.g., under 1 second on average)
        // Note: Detection involves some I/O, so it won't be instant
        XCTAssertLessThan(averageTime, 1.0, "inspectSystem() is too slow")
    }

    func testMakePlanPerformance() async {
        let engine = InstallerEngine()
        let context = await engine.inspectSystem()

        // Warm up
        _ = await engine.makePlan(for: .install, context: context)

        let iterations = 100
        let start = Date()
        for _ in 0 ..< iterations {
            _ = await engine.makePlan(for: .install, context: context)
        }
        let duration = Date().timeIntervalSince(start)
        let averageTime = duration / Double(iterations)

        print("Average makePlan() time: \(averageTime) seconds")

        // Planning should be very fast (memory only mostly)
        XCTAssertLessThan(averageTime, 0.01, "makePlan() is too slow")
    }
}
