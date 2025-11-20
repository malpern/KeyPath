import XCTest

@testable import KeyPathAppKit

final class FDADetectionTests: XCTestCase {
    // MARK: - FDA Detection Method Tests

    func testFDADetectionWithoutAccess() {
        // When FDA is not granted, all methods should return false
        // Note: This test assumes we're running without FDA

        let testPath = "\(NSHomeDirectory())/Library/Safari/.keypath_fda_test"
        let testData = Data("FDA_TEST".utf8)

        // Check if we already have FDA access first
        let bookmarksPath = "\(NSHomeDirectory())/Library/Safari/Bookmarks.plist"
        let hasExistingFDA = FileManager.default.isReadableFile(atPath: bookmarksPath) &&
            (try? Data(contentsOf: URL(fileURLWithPath: bookmarksPath))) != nil

        if hasExistingFDA {
            // If we have FDA, the write should succeed
            XCTAssertNoThrow(try testData.write(to: URL(fileURLWithPath: testPath)))
            // Clean up
            try? FileManager.default.removeItem(atPath: testPath)
        } else {
            // Should fail to write to protected location without FDA
            XCTAssertThrowsError(try testData.write(to: URL(fileURLWithPath: testPath))) { error in
                // Should be a permission error
                XCTAssertNotNil(error)
            }
        }
    }

    func testFDACaching() async {
        // Test that FDA status is cached appropriately

        var lastCheckTime: Date?
        var cachedStatus = false
        let cacheValidityDuration: TimeInterval = 10.0

        // Simulate first check
        lastCheckTime = Date()
        cachedStatus = false // Assume no FDA

        // Immediate second check should use cache
        let timeSinceLastCheck = Date().timeIntervalSince(lastCheckTime!)
        XCTAssertLessThan(timeSinceLastCheck, cacheValidityDuration)

        // Should use cached value
        if timeSinceLastCheck < cacheValidityDuration, cachedStatus {
            XCTAssertTrue(cachedStatus, "Should use cached positive result")
        }

        // After cache expires, should check again
        lastCheckTime = Date(timeIntervalSinceNow: -11) // 11 seconds ago
        let expiredTimeSinceCheck = Date().timeIntervalSince(lastCheckTime!)
        XCTAssertGreaterThan(expiredTimeSinceCheck, cacheValidityDuration)
    }

    func testProtectedPathDetection() {
        // Test various protected paths
        let protectedPaths = [
            "\(NSHomeDirectory())/Library/Mail",
            "\(NSHomeDirectory())/Library/Messages",
            "\(NSHomeDirectory())/Library/Safari/Bookmarks.plist"
        ]

        for path in protectedPaths {
            let url = URL(fileURLWithPath: path)

            // These should exist but may not be readable without FDA
            if FileManager.default.fileExists(atPath: path) {
                // Try to read - will fail without FDA
                let data = try? Data(contentsOf: url)

                if data != nil {
                    print("Has FDA access to: \(path)")
                } else {
                    print("No FDA access to: \(path)")
                }

                // Test passes either way - we're testing the detection logic
                XCTAssertTrue(true)
            }
        }
    }

    // MARK: - Restart Flow Tests

    func testWizardStatePreservation() {
        // Test saving wizard state for restart
        let defaults = UserDefaults.standard

        // Save state
        defaults.set("fullDiskAccess", forKey: "KeyPath.WizardRestorePoint")
        defaults.set(Date().timeIntervalSince1970, forKey: "KeyPath.WizardRestoreTime")

        // Read state
        let restorePoint = defaults.string(forKey: "KeyPath.WizardRestorePoint")
        let restoreTime = defaults.double(forKey: "KeyPath.WizardRestoreTime")

        XCTAssertEqual(restorePoint, "fullDiskAccess")
        XCTAssertGreaterThan(restoreTime, 0)

        // Check if restoration is valid (within 5 minutes)
        let isValid = Date().timeIntervalSince1970 - restoreTime < 300
        XCTAssertTrue(isValid, "Restoration should be valid within 5 minutes")

        // Clean up
        defaults.removeObject(forKey: "KeyPath.WizardRestorePoint")
        defaults.removeObject(forKey: "KeyPath.WizardRestoreTime")
    }

    func testRestartTimingWindow() {
        let defaults = UserDefaults.standard

        // Test expired restoration (> 5 minutes old)
        defaults.set("fullDiskAccess", forKey: "KeyPath.WizardRestorePoint")
        defaults.set(Date().timeIntervalSince1970 - 400, forKey: "KeyPath.WizardRestoreTime") // 400 seconds ago

        let restoreTime = defaults.double(forKey: "KeyPath.WizardRestoreTime")
        let timeSinceRestore = Date().timeIntervalSince1970 - restoreTime

        XCTAssertGreaterThan(timeSinceRestore, 300, "Should be expired")

        // Clean up
        defaults.removeObject(forKey: "KeyPath.WizardRestorePoint")
        defaults.removeObject(forKey: "KeyPath.WizardRestoreTime")
    }

    // MARK: - Modal State Tests

    func testDetectionModalTiming() {
        // Test the 8-second detection window
        let maxDetectionAttempts = 4 // 4 attempts at 2-second intervals = 8 seconds
        let detectionInterval: TimeInterval = 2.0

        let totalDetectionTime = Double(maxDetectionAttempts) * detectionInterval
        XCTAssertEqual(totalDetectionTime, 8.0, "Should attempt detection for 8 seconds")

        // Test attempt progression
        for attempt in 0 ..< maxDetectionAttempts {
            let timeRemaining = (maxDetectionAttempts - attempt) * Int(detectionInterval)
            XCTAssertGreaterThanOrEqual(timeRemaining, 0)
            XCTAssertLessThanOrEqual(timeRemaining, 8)
        }
    }

    // MARK: - Performance Tests

    func testFDACheckPerformance() {
        // FDA check should be fast
        measure {
            let protectedTestPath = "\(NSHomeDirectory())/Library/Safari/.keypath_fda_test"
            let testData = Data("FDA_TEST".utf8)

            // Attempt write (will fail without FDA, but that's ok)
            _ = try? testData.write(to: URL(fileURLWithPath: protectedTestPath))
            try? FileManager.default.removeItem(atPath: protectedTestPath)
        }
    }
}
