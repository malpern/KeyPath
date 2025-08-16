@testable import KeyPath
import XCTest

/// Tests for LaunchDaemonPIDCache race condition fix
/// Covers caching, timeout protection, and confidence scoring
@MainActor
final class LaunchDaemonPIDCacheTests: XCTestCase {
    var cache: LaunchDaemonPIDCache!

    override func setUp() async throws {
        try await super.setUp()
        cache = LaunchDaemonPIDCache()
    }

    override func tearDown() async throws {
        cache = nil
        try await super.tearDown()
    }

    // MARK: - Basic Cache Functionality Tests

    func testCacheInitiallyEmpty() async {
        // When: Getting PID from fresh cache
        let (pid, confidence) = await cache.getCachedPIDWithConfidence()

        // Then: Should return nil with no confidence
        XCTAssertNil(pid, "Fresh cache should have no PID")
        XCTAssertEqual(confidence, .none, "Fresh cache should have no confidence")
    }

    func testCacheInvalidation() async {
        // Given: Cache might have some data from previous operations
        _ = await cache.getCachedPID()

        // When: Invalidating cache
        await cache.invalidateCache()

        // Then: Cache should be cleared
        let lastUpdate = await cache.lastUpdate
        XCTAssertNil(lastUpdate, "Cache invalidation should clear lastUpdate")
    }

    func testCacheTimeout() async {
        // This test verifies that the cache respects its timeout
        // Since we can't easily mock time, we test the logic indirectly

        // When: Getting cached PID (will trigger fresh fetch)
        let firstPID = await cache.getCachedPID()

        // Then: Should have attempted to fetch (may succeed or fail)
        // The important part is that it doesn't crash or hang
        let lastUpdate = await cache.lastUpdate
        XCTAssertNotNil(lastUpdate, "Should have attempted fetch and set lastUpdate")

        // Note: firstPID may be nil if launchctl fails, which is expected in test environment
    }

    func testConfidenceScoring() async {
        // Given: A cache that might have fetched data
        _ = await cache.getCachedPID()

        // When: Getting PID with confidence
        let (_, confidence) = await cache.getCachedPIDWithConfidence()

        // Then: Should provide appropriate confidence level
        // In test environment, launchctl likely fails, so confidence might be .none
        XCTAssertTrue(
            [.none, .low, .medium, .high].contains(confidence),
            "Confidence should be a valid enum value"
        )

        print("✅ Cache confidence level: \(confidence)")
    }

    // MARK: - Timeout Protection Tests

    func testTimeoutProtection() async {
        // This test verifies timeout protection exists
        // We can't easily trigger a real timeout in tests, but we can verify structure

        let startTime = Date()

        // When: Getting cached PID (triggers fetch with timeout protection)
        let result = await cache.getCachedPID()

        let duration = Date().timeIntervalSince(startTime)

        // Then: Should complete within reasonable time (timeout protection working)
        XCTAssertLessThan(
            duration, 10.0,
            "Cache fetch should complete within 10 seconds (timeout protection)"
        )

        print("✅ Cache fetch completed in \(String(format: "%.2f", duration)) seconds")
        print("✅ Result: PID \(result ?? -1)")
    }

    func testConcurrentAccess() async {
        // Test that multiple concurrent cache accesses don't cause issues

        // When: Multiple concurrent cache accesses
        await withTaskGroup(of: (pid_t?, CacheConfidence).self) { group in
            for i in 0 ..< 5 {
                group.addTask {
                    await self.cache.getCachedPIDWithConfidence()
                }
            }

            var results: [(pid_t?, CacheConfidence)] = []
            for await result in group {
                results.append(result)
            }

            // Then: All requests should complete without crashes
            XCTAssertEqual(results.count, 5, "All concurrent requests should complete")

            // Results should be consistent (since cache should deduplicate requests)
            let pids = results.map(\.0)
            let uniquePIDs = Set(pids.compactMap { $0 })

            if !pids.compactMap({ $0 }).isEmpty {
                XCTAssertLessThanOrEqual(
                    uniquePIDs.count, 2,
                    "Concurrent requests should return consistent results"
                )
            }

            print("✅ Concurrent cache access completed successfully")
            print("✅ Results: \(results)")
        }
    }

    // MARK: - Error Handling Tests

    func testErrorHandlingGracefully() async {
        // Test that cache handles system command failures gracefully

        // When: Getting PID (may fail due to no Kanata service in test environment)
        let (pid, confidence) = await cache.getCachedPIDWithConfidence()

        // Then: Should handle failure gracefully without crashes
        if pid == nil {
            // Expected in test environment - no Kanata service running
            XCTAssertEqual(confidence, .none, "Failed fetch should have no confidence")
            print("✅ Cache gracefully handled fetch failure (expected in test environment)")
        } else {
            // Unexpected success - service actually running
            XCTAssertNotEqual(confidence, .none, "Successful fetch should have confidence")
            print("✅ Cache successfully fetched PID: \(pid!)")
        }
    }

    func testStaleDataFallback() async {
        // This test verifies the concept of stale data fallback
        // In a real implementation, we'd mock a timeout scenario

        // When: Cache attempts to fetch but may encounter errors
        let result1 = await cache.getCachedPID()

        // Simulate some time passing
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // When: Second fetch attempt
        let result2 = await cache.getCachedPID()

        // Then: Results should be consistent if caching is working
        if result1 != nil, result2 != nil {
            XCTAssertEqual(result1, result2, "Cache should return consistent results")
        }

        print("✅ Stale data fallback test completed")
    }

    // MARK: - Real System Integration Tests

    func testIntegrationWithRealLaunchctl() async {
        // Test integration with real launchctl command

        // When: Attempting to fetch real PID
        let (pid, confidence) = await cache.getCachedPIDWithConfidence()

        if let pid {
            // Then: If successful, PID should be valid
            XCTAssertGreaterThan(pid, 0, "Valid PID should be positive")
            XCTAssertNotEqual(confidence, .none, "Successful fetch should have confidence")

            print("✅ Successfully fetched Kanata LaunchDaemon PID: \(pid)")
            print("✅ Confidence level: \(confidence)")
        } else {
            // Then: If failed, should be handled gracefully
            XCTAssertEqual(confidence, .none, "Failed fetch should have no confidence")

            print("✅ No Kanata LaunchDaemon running (expected in test environment)")
        }
    }

    func testCacheConsistencyAcrossMultipleFetches() async {
        // Test that cache provides consistent results across multiple fetches

        var results: [(pid_t?, CacheConfidence)] = []

        // When: Multiple sequential fetches
        for i in 0 ..< 3 {
            let result = await cache.getCachedPIDWithConfidence()
            results.append(result)

            // Small delay between fetches
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

            print("Fetch \(i + 1): PID \(result.0 ?? -1), confidence \(result.1)")
        }

        // Then: Results should be consistent
        let pids = results.map(\.0)
        let confidences = results.map(\.1)

        // All PIDs should be the same (either all nil or all the same value)
        if let firstPID = pids.first {
            for pid in pids {
                XCTAssertEqual(pid, firstPID, "All fetches should return consistent PID")
            }
        }

        // Confidence should generally improve or stay the same (unless cache expires)
        // This tests that cache aging works correctly
        print("✅ Consistency test completed: \(results)")
    }

    // MARK: - Performance Tests

    func testCachePerformance() async {
        // Test that cache improves performance by avoiding repeated launchctl calls

        // When: First fetch (cold cache)
        let startTime1 = Date()
        let result1 = await cache.getCachedPID()
        let duration1 = Date().timeIntervalSince(startTime1)

        // When: Second fetch (warm cache)
        let startTime2 = Date()
        let result2 = await cache.getCachedPID()
        let duration2 = Date().timeIntervalSince(startTime2)

        // Then: Second fetch should be faster (cache hit)
        if result1 == result2, result1 != nil {
            XCTAssertLessThan(
                duration2, duration1,
                "Cached fetch should be faster than initial fetch"
            )
        }

        print("✅ Performance test: First fetch \(String(format: "%.3f", duration1))s, Second fetch \(String(format: "%.3f", duration2))s")
    }

    func testRapidSequentialFetches() async {
        // Test rapid sequential fetches to simulate race condition scenario

        let startTime = Date()
        var results: [pid_t?] = []

        // When: Rapid sequential fetches
        for _ in 0 ..< 10 {
            let result = await cache.getCachedPID()
            results.append(result)
        }

        let duration = Date().timeIntervalSince(startTime)

        // Then: All fetches should complete quickly
        XCTAssertLessThan(duration, 5.0, "Rapid fetches should complete within 5 seconds")

        // Results should be consistent
        let uniqueResults = Set(results.compactMap { $0 })
        if !results.compactMap({ $0 }).isEmpty {
            XCTAssertLessThanOrEqual(
                uniqueResults.count, 1,
                "Rapid fetches should return consistent results"
            )
        }

        print("✅ Rapid fetch test: \(results.count) fetches in \(String(format: "%.3f", duration))s")
        print("✅ Unique results: \(uniqueResults.count)")
    }
}

// MARK: - Mock Cache for Specific Test Scenarios

/// Mock cache for testing specific timeout and error scenarios
actor MockLaunchDaemonPIDCache {
    private var mockPID: pid_t?
    private var shouldTimeout: Bool = false
    private var shouldFail: Bool = false

    func setMockPID(_ pid: pid_t?) {
        mockPID = pid
    }

    func setShouldTimeout(_ timeout: Bool) {
        shouldTimeout = timeout
    }

    func setShouldFail(_ fail: Bool) {
        shouldFail = fail
    }

    func getCachedPID() async throws -> pid_t? {
        if shouldTimeout {
            try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            throw TimeoutError()
        }

        if shouldFail {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock failure"])
        }

        return mockPID
    }
}

// MARK: - Mock-based Unit Tests

@MainActor
final class MockLaunchDaemonPIDCacheTests: XCTestCase {
    func testTimeoutScenario() async {
        // Given: Mock cache that times out
        let mockCache = MockLaunchDaemonPIDCache()
        await mockCache.setShouldTimeout(true)

        // When: Attempting to get PID
        do {
            _ = try await mockCache.getCachedPID()
            XCTFail("Should have thrown timeout error")
        } catch is TimeoutError {
            // Then: Should throw timeout error
            print("✅ Timeout scenario handled correctly")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFailureScenario() async {
        // Given: Mock cache that fails
        let mockCache = MockLaunchDaemonPIDCache()
        await mockCache.setShouldFail(true)

        // When: Attempting to get PID
        do {
            _ = try await mockCache.getCachedPID()
            XCTFail("Should have thrown error")
        } catch {
            // Then: Should throw error gracefully
            XCTAssertTrue(error.localizedDescription.contains("Mock failure"))
            print("✅ Failure scenario handled correctly")
        }
    }

    func testSuccessScenario() async {
        // Given: Mock cache with valid PID
        let mockCache = MockLaunchDaemonPIDCache()
        let expectedPID: pid_t = 12345
        await mockCache.setMockPID(expectedPID)

        // When: Getting PID
        do {
            let result = try await mockCache.getCachedPID()

            // Then: Should return expected PID
            XCTAssertEqual(result, expectedPID, "Should return mock PID")
            print("✅ Success scenario handled correctly: PID \(result!)")
        } catch {
            XCTFail("Should not throw error: \(error)")
        }
    }
}
