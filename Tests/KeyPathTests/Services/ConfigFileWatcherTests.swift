@preconcurrency import XCTest

@testable import KeyPathAppKit

@MainActor
final class ConfigFileWatcherTests: XCTestCase {
    func testDebouncePreventsMultipleCallbacks() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let filePath = tempDir.appendingPathComponent("config.kbd").path
        FileManager.default.createFile(atPath: filePath, contents: Data())

        let watcher = ConfigFileWatcher()
        var callbackCount = 0
        let expectation = expectation(description: "File change processed")
        watcher.startWatching(path: filePath) {
            callbackCount += 1
            expectation.fulfill()
        }

        try "one".write(toFile: filePath, atomically: true, encoding: .utf8)
        try "two".write(toFile: filePath, atomically: true, encoding: .utf8)
        try "three".write(toFile: filePath, atomically: true, encoding: .utf8)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(callbackCount, 1)
        watcher.stopWatching()
    }
}
