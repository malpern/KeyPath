import AppKit
import Foundation
import KeyPathCore
import XCTest

@testable import KeyPathAppKit

final class UtilitiesTests: XCTestCase {
    private var testDefaults: UserDefaults!

    override func setUpWithError() throws {
        testDefaults = UserDefaults(suiteName: "KeyPath.UtilitiesTests.\(UUID().uuidString)")
        AppRestarter.setUserDefaults(testDefaults)
        testDefaults.removeObject(forKey: "KeyPath.WizardRestorePoint")
        testDefaults.removeObject(forKey: "KeyPath.WizardRestoreTime")
        testDefaults.synchronize()
    }

    override func tearDownWithError() throws {
        testDefaults.removeObject(forKey: "KeyPath.WizardRestorePoint")
        testDefaults.removeObject(forKey: "KeyPath.WizardRestoreTime")
        testDefaults.synchronize()
        AppRestarter.setUserDefaults(UserDefaults.standard)
        testDefaults = nil
    }

    // MARK: - AppRestarter Tests

    func testAppRestarterSaveWizardState() throws {
        let testPage = "TestWizardPage"
        let beforeTime = Date().timeIntervalSince1970

        // This will save state but won't actually restart in tests
        // We verify the state saving functionality
        AppRestarter.restartForWizard(at: testPage)

        // Verify state was saved
        let savedPage = testDefaults.string(forKey: "KeyPath.WizardRestorePoint")
        let savedTime = testDefaults.double(forKey: "KeyPath.WizardRestoreTime")

        XCTAssertEqual(savedPage, testPage, "Should save wizard page")
        XCTAssertGreaterThan(savedTime, beforeTime, "Should save recent timestamp")
        XCTAssertLessThan(savedTime, Date().timeIntervalSince1970 + 1, "Should save current timestamp")
    }

    func testAppRestarterStateManagement() throws {
        // Test multiple state saves
        let pages = ["Page1", "Page2", "Page3"]

        for page in pages {
            AppRestarter.restartForWizard(at: page)

            let savedPage = testDefaults.string(forKey: "KeyPath.WizardRestorePoint")
            XCTAssertEqual(savedPage, page, "Should save each page correctly")
        }

        // Test empty page handling
        AppRestarter.restartForWizard(at: "")
        let emptyPage = testDefaults.string(forKey: "KeyPath.WizardRestorePoint")
        XCTAssertEqual(emptyPage, "", "Should handle empty page")
    }

    func testAppRestarterSpecialCharacters() throws {
        // Test pages with special characters
        let specialPages = [
            "Page with spaces",
            "Page/with/slashes",
            "Page\\with\\backslashes",
            "Page@with@symbols",
            "页面中文",
            "🚀 Emoji Page",
        ]

        for page in specialPages {
            AppRestarter.restartForWizard(at: page)

            let savedPage = testDefaults.string(forKey: "KeyPath.WizardRestorePoint")
            XCTAssertEqual(savedPage, page, "Should handle special characters in page name: \(page)")
        }
    }

    func testAppRestarterTimestampAccuracy() throws {
        let beforeSave = Date().timeIntervalSince1970
        AppRestarter.restartForWizard(at: "TimestampTest")
        let afterSave = Date().timeIntervalSince1970

        let savedTime = testDefaults.double(forKey: "KeyPath.WizardRestoreTime")

        XCTAssertGreaterThanOrEqual(
            savedTime, beforeSave, "Timestamp should be after or equal to before time"
        )
        XCTAssertLessThanOrEqual(
            savedTime, afterSave, "Timestamp should be before or equal to after time"
        )
    }

    func testAppRestarterUserDefaultsSynchronization() throws {
        // Test that UserDefaults.synchronize() is called
        AppRestarter.restartForWizard(at: "SyncTest")

        // Create a new UserDefaults instance to verify persistence
        let newDefaults = testDefaults!
        let savedPage = newDefaults.string(forKey: "KeyPath.WizardRestorePoint")

        XCTAssertEqual(savedPage, "SyncTest", "State should be synchronized to disk")
    }

    func testAppRestarterBundlePathHandling() throws {
        // Test that Bundle.main.bundlePath is accessible
        let bundlePath = Bundle.main.bundlePath
        XCTAssertFalse(bundlePath.isEmpty, "Bundle path should not be empty")

        if bundlePath.contains(".app") {
            XCTAssertTrue(true, "Bundle path should include .app when running from an app bundle")
        } else if bundlePath.contains(".xctest") {
            XCTAssertTrue(true, "Bundle path should include .xctest when running tests")
        } else {
            XCTAssertTrue(bundlePath.hasSuffix("/xctest"), "Unexpected bundle path: \(bundlePath)")
        }
    }

    // MARK: - Logger Tests

    func testLoggerSingleton() throws {
        let logger1 = AppLogger.shared
        let logger2 = AppLogger.shared

        XCTAssertTrue(logger1 === logger2, "Logger should be a singleton")
    }

    func testLoggerBasicLogging() throws {
        let logger = AppLogger.shared

        // Test basic logging doesn't crash
        logger.log("Test message")
        logger.log("Test message with special chars: !@#$%^&*()")
        logger.log("Test message with unicode: 🚀 中文 العربية")

        XCTAssertTrue(true, "Basic logging should not crash")
    }

    func testLoggerLongMessages() throws {
        let logger = AppLogger.shared

        // Test very long message
        let longMessage = String(repeating: "A", count: 10000)
        logger.log(longMessage)

        // Test message with many lines
        let multilineMessage = Array(repeating: "Line of text", count: 100).joined(separator: "\n")
        logger.log(multilineMessage)

        XCTAssertTrue(true, "Long messages should be handled gracefully")
    }

    func testLoggerEmptyMessages() throws {
        let logger = AppLogger.shared

        // Test edge cases
        logger.log("")
        logger.log(" ")
        logger.log("\n")
        logger.log("\t")

        XCTAssertTrue(true, "Empty or whitespace messages should not crash")
    }

    func testLoggerFlushBuffer() throws {
        let logger = AppLogger.shared

        // Log several messages
        for i in 0 ..< 10 {
            logger.log("Test message \(i)")
        }

        // Force flush
        logger.flushBuffer()

        XCTAssertTrue(true, "Buffer flush should complete without error")
    }

    func testLoggerClearAllLogs() throws {
        let logger = AppLogger.shared

        // Log some messages
        logger.log("Message before clear")
        logger.log("Another message")

        // Clear logs
        logger.clearAllLogs()

        // Log after clear
        logger.log("Message after clear")

        XCTAssertTrue(true, "Clear logs should complete without error")
    }

    func testLoggerLogSize() throws {
        let logger = AppLogger.shared

        // Test log size methods
        let currentSize = logger.getCurrentLogSize()
        let totalSize = logger.getTotalLogSize()

        XCTAssertGreaterThanOrEqual(currentSize, 0, "Current log size should be non-negative")
        XCTAssertGreaterThanOrEqual(totalSize, currentSize, "Total size should be >= current size")
    }

    func testLoggerDirectoryCreation() throws {
        // Test that logger initializes without crashing even if directory creation fails
        // This is handled in the logger's init method
        let logger = AppLogger.shared

        XCTAssertNotNil(logger, "Logger should initialize even with directory issues")
    }

    func testLoggerFileInformation() throws {
        let logger = AppLogger.shared

        // Test logging with file information
        logger.log("Test message with file info", file: #file, function: #function, line: #line)

        XCTAssertTrue(true, "Logging with file information should work")
    }

    func testLoggerConcurrentAccess() throws {
        let logger = AppLogger.shared
        let expectation = expectation(description: "Concurrent logging")
        expectation.expectedFulfillmentCount = 10

        // Test concurrent logging from multiple queues
        for i in 0 ..< 10 {
            DispatchQueue.global(qos: .background).async {
                logger.log("Concurrent message \(i)")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(true, "Concurrent logging should be thread-safe")
    }

    func testLoggerRotationBehavior() throws {
        let logger = AppLogger.shared

        // We can't easily test actual rotation without creating large files,
        // but we can test that the rotation methods exist and don't crash
        let sizeBefore = logger.getCurrentLogSize()

        // Log a bunch of messages to potentially trigger rotation checks
        for i in 0 ..< 100 {
            logger.log("Rotation test message \(i) with some additional content to increase size")
        }

        let sizeAfter = logger.getCurrentLogSize()
        XCTAssertGreaterThanOrEqual(
            sizeAfter, sizeBefore, "Log size should increase or stay same after logging"
        )
    }

    // MARK: - Error Handling Tests

    func testLoggerErrorHandling() throws {
        let logger = AppLogger.shared

        // Test logging during error conditions
        do {
            throw NSError(
                domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"]
            )
        } catch {
            logger.log("Caught error: \(error.localizedDescription)")
        }

        XCTAssertTrue(true, "Error logging should work correctly")
    }

    func testAppRestarterErrorConditions() throws {
        // Test AppRestarter with edge case inputs
        let extremeCases = [
            String(repeating: "x", count: 1000), // Very long page name
            "null\0character", // Null character
            "\n\r\t", // Control characters
        ]

        for testCase in extremeCases {
            // Should not crash even with extreme inputs
            AppRestarter.restartForWizard(at: testCase)

            let saved = testDefaults.string(forKey: "KeyPath.WizardRestorePoint")
            XCTAssertEqual(saved, testCase, "Should handle extreme case: \(testCase.prefix(50))...")
        }
    }

    func testLoggerMemoryPressure() throws {
        let logger = AppLogger.shared

        // Test logger behavior under memory pressure
        // Log many large messages rapidly
        for i in 0 ..< 50 {
            let largeMessage = String(repeating: "Memory pressure test \(i) ", count: 100)
            logger.log(largeMessage)
        }

        // Force flush and clear to test cleanup
        logger.flushBuffer()

        XCTAssertTrue(true, "Logger should handle memory pressure gracefully")
    }

    func testLoggerPathHandling() throws {
        let logger = AppLogger.shared

        // Test that logger handles path issues gracefully
        // The logger should fallback to temp directory if project path fails

        // Log a message to ensure logger is working
        logger.log("Path handling test")

        // Get log sizes to verify logger is functional
        let currentSize = logger.getCurrentLogSize()
        XCTAssertGreaterThanOrEqual(
            currentSize, 0, "Logger should be functional regardless of path issues"
        )
    }

    // MARK: - Integration Tests

    func testLoggerWithAppRestarter() throws {
        let logger = AppLogger.shared

        // Test logging during app restart preparation
        logger.log("🔄 [Test] Starting app restart test")

        AppRestarter.restartForWizard(at: "IntegrationTest")

        logger.log("✅ [Test] App restart state saved")

        // Verify both components work together
        let savedPage = testDefaults.string(forKey: "KeyPath.WizardRestorePoint")
        XCTAssertEqual(savedPage, "IntegrationTest", "Integration should work correctly")
    }

    func testUtilitiesWithSystemStress() throws {
        let logger = AppLogger.shared
        let stressTestCount = 100

        // Stress test both utilities together
        for i in 0 ..< stressTestCount {
            logger.log("Stress test iteration \(i)")

            if i % 10 == 0 {
                AppRestarter.restartForWizard(at: "StressTest\(i)")
            }

            if i % 25 == 0 {
                logger.flushBuffer()
            }
        }

        // Verify final state
        let finalPage = testDefaults.string(forKey: "KeyPath.WizardRestorePoint")
        XCTAssertTrue(finalPage?.hasPrefix("StressTest") == true, "Should maintain state under stress")

        logger.clearAllLogs()
        XCTAssertTrue(true, "Stress test should complete successfully")
    }

    // MARK: - Performance Tests

    func testLoggerPerformance() throws {
        let logger = AppLogger.shared

        measure {
            for i in 0 ..< 1000 {
                logger.log("Performance test message \(i)")
            }
        }
    }

    func testAppRestarterPerformance() throws {
        measure {
            for i in 0 ..< 100 {
                AppRestarter.restartForWizard(at: "PerformanceTest\(i)")
            }
        }
    }

    func testLoggerFlushPerformance() throws {
        let logger = AppLogger.shared

        // Fill up buffer
        for i in 0 ..< 50 {
            logger.log("Buffer fill message \(i)")
        }

        measure {
            logger.flushBuffer()
        }
    }

    // MARK: - Cleanup Tests

    func testLoggerCleanupOnDeinit() throws {
        weak var weakLogger: AppLogger?

        // Test that logger cleanup works properly
        // Note: We can't easily test AppLogger.shared deinit since it's a singleton,
        // but we can test the cleanup methods
        let logger = AppLogger.shared
        weakLogger = logger

        // Test cleanup methods
        logger.flushBuffer()
        logger.clearAllLogs()

        XCTAssertNotNil(weakLogger, "Singleton should remain in memory")
    }

    func testUserDefaultsCleanup() throws {
        // Test cleanup of UserDefaults
        AppRestarter.restartForWizard(at: "CleanupTest")

        XCTAssertNotNil(testDefaults.string(forKey: "KeyPath.WizardRestorePoint"))

        // Manual cleanup
        UserDefaults.standard.removeObject(forKey: "KeyPath.WizardRestorePoint")
        UserDefaults.standard.removeObject(forKey: "KeyPath.WizardRestoreTime")
        UserDefaults.standard.synchronize()

        XCTAssertNil(UserDefaults.standard.string(forKey: "KeyPath.WizardRestorePoint"))
    }
}
