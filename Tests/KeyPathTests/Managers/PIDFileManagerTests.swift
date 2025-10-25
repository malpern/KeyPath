import XCTest
@testable import KeyPath

final class PIDFileManagerTests: XCTestCase {
    private var tempHome: URL!

    override func setUpWithError() throws {
        tempHome = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kp-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        setenv("HOME", tempHome.path, 1)
        // Ensure clean slate: if type was previously initialized in other tests, remove any existing file
        try? PIDFileManager.removePID()
    }

    override func tearDownWithError() throws {
        try? PIDFileManager.removePID()
        try? FileManager.default.removeItem(at: tempHome)
    }

    func testPathResolvesUnderHome() {
        let path = PIDFileManager.pidFilePath
        XCTAssertTrue(path.contains(tempHome.path))
        XCTAssertTrue(path.hasSuffix("Library/Application Support/KeyPath/kanata.pid"))
    }

    func testWriteReadAndRemovePID() throws {
        // Write record for current process
        try PIDFileManager.writePID(getpid(), command: "KeyPathTests")
        guard let record = PIDFileManager.readPID() else { return XCTFail("Expected PID record") }
        XCTAssertEqual(record.pid, getpid())
        XCTAssertFalse(record.isStale)

        // Ownership should be true if process is running
        let ownership = PIDFileManager.checkOwnership()
        XCTAssertTrue(ownership.owned)
        XCTAssertEqual(ownership.pid, getpid())

        // Remove and ensure gone
        try PIDFileManager.removePID()
        XCTAssertNil(PIDFileManager.readPID())
    }

    func testCorruptedFileIsHandledGracefully() throws {
        // Create directory and write junk
        let path = PIDFileManager.pidFilePath
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try "junk".data(using: .utf8)!.write(to: URL(fileURLWithPath: path))

        // readPID should clean up and return nil
        XCTAssertNil(PIDFileManager.readPID())
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }
}

